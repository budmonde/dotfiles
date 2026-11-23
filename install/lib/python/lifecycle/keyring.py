import ctypes
import os
import platform
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

from .core import diagnostic


def ubuntu_noble_amd64():
    if platform.machine() != "x86_64":
        return False
    try:
        release = Path("/etc/os-release").read_text(encoding="utf-8").splitlines()
    except OSError:
        return False
    return "ID=ubuntu" in release and "VERSION_CODENAME=noble" in release


def linux_keyring_prefix():
    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    return data_home / "dotfiles/keyring" / ("ubuntu-noble-" + platform.machine())


def linux_keyring_command(name):
    environment = os.environ.copy()
    if ubuntu_noble_amd64():
        prefix = linux_keyring_prefix()
        executable = prefix / "usr/bin" / name
        if executable.is_file() and os.access(executable, os.X_OK):
            libraries = [
                str(path) for path in sorted((prefix / "usr/lib").glob("*-linux-*"))
                if path.is_dir()
            ]
            if environment.get("LD_LIBRARY_PATH"):
                libraries.append(environment["LD_LIBRARY_PATH"])
            if libraries:
                environment["LD_LIBRARY_PATH"] = os.pathsep.join(libraries)
            return str(executable), environment
    return shutil.which(name), environment


def linux_keyring_locked():
    if not shutil.which("dbus-send") or not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        return None
    result = _run(
        [
            "dbus-send",
            "--session",
            "--print-reply",
            "--reply-timeout=2000",
            "--dest=org.freedesktop.secrets",
            "/org/freedesktop/secrets/aliases/default",
            "org.freedesktop.DBus.Properties.Get",
            "string:org.freedesktop.Secret.Collection",
            "string:Locked",
        ]
    )
    if result is not None and result.returncode == 0:
        tail = result.stdout.split()[-3:]
        if tail[:2] == ["variant", "boolean"] and tail[-1] in {"true", "false"}:
            return tail[-1] == "true"
    return None


def linux_keyring_ready():
    return linux_keyring_locked() is False


def _run(arguments, **options):
    if "input" not in options:
        options["stdin"] = subprocess.DEVNULL
    try:
        return subprocess.run(
            arguments,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
            check=False,
            **options,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def _linux_round_trip(target, value):
    executable, environment = linux_keyring_command("secret-tool")
    if not executable:
        diagnostic("The Secret Service readiness check requires secret-tool.")
        return False
    attributes = ["dotfiles-keyring-check", target]
    stored = _run([executable, "store", "--label=Dotfiles keyring check", *attributes],
                  input=value, env=environment)
    try:
        found = _run([executable, "lookup", *attributes], env=environment)
    finally:
        cleared = _run([executable, "clear", *attributes], env=environment)
    return (
        stored is not None and stored.returncode == 0
        and found is not None and found.returncode == 0 and found.stdout.rstrip("\n") == value
        and cleared is not None and cleared.returncode == 0
    )


def _mac_keyring_ready():
    security = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
    foundation = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    keychain = ctypes.c_void_p()
    if security.SecKeychainCopyDefault(ctypes.byref(keychain)) != 0:
        return False
    try:
        status = ctypes.c_uint32()
        unlocked_readable_writable = 0x7
        return (
            security.SecKeychainGetStatus(keychain, ctypes.byref(status)) == 0
            and status.value & unlocked_readable_writable == unlocked_readable_writable
        )
    finally:
        foundation.CFRelease(keychain)


def _mac_round_trip(target, value):
    identity = ["-s", target, "-a", "dotfiles"]
    stored = _run(["security", "add-generic-password", *identity, "-w", value])
    try:
        found = _run(["security", "find-generic-password", *identity, "-w"])
    finally:
        cleared = _run(["security", "delete-generic-password", *identity])
    return (
        stored is not None and stored.returncode == 0
        and found is not None and found.returncode == 0 and found.stdout.rstrip("\n") == value
        and cleared is not None and cleared.returncode == 0
    )


def _windows_keyring(target, value=None):
    from ctypes import wintypes as wt

    class Credential(ctypes.Structure):
        _fields_ = [
            ("Flags", wt.DWORD),
            ("Type", wt.DWORD),
            ("TargetName", wt.LPWSTR),
            ("Comment", wt.LPWSTR),
            ("LastWritten", wt.FILETIME),
            ("CredentialBlobSize", wt.DWORD),
            ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
            ("Persist", wt.DWORD),
            ("AttributeCount", wt.DWORD),
            ("Attributes", ctypes.c_void_p),
            ("TargetAlias", wt.LPWSTR),
            ("UserName", wt.LPWSTR),
        ]

    api = ctypes.WinDLL("Advapi32.dll", use_last_error=True)
    api.CredReadW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD,
                              ctypes.POINTER(ctypes.POINTER(Credential))]
    api.CredWriteW.argtypes = [ctypes.POINTER(Credential), wt.DWORD]
    api.CredDeleteW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD]
    api.CredFree.argtypes = [ctypes.c_void_p]
    api.CredFree.restype = None
    generic = 1
    data = ctypes.POINTER(Credential)()
    if value is None:
        if api.CredReadW(target, generic, 0, ctypes.byref(data)):
            api.CredFree(data)
            return True
        return ctypes.get_last_error() == 1168  # The credential set exists, but this item does not.

    secret = value.encode("ascii")
    blob = (ctypes.c_ubyte * len(secret)).from_buffer_copy(secret)
    credential = Credential(Type=generic, TargetName=target, UserName="dotfiles",
                            CredentialBlobSize=len(secret), CredentialBlob=blob, Persist=1)
    if not api.CredWriteW(ctypes.byref(credential), 0):
        return False
    try:
        if api.CredReadW(target, generic, 0, ctypes.byref(data)):
            try:
                matches = ctypes.string_at(data.contents.CredentialBlob,
                                           data.contents.CredentialBlobSize) == secret
            finally:
                api.CredFree(data)
        else:
            matches = False
    finally:
        cleared = api.CredDeleteW(target, generic, 0)
    return matches and bool(cleared)


def keyring_ready():
    if sys.platform.startswith("linux"):
        if linux_keyring_ready():
            return True
        diagnostic(
            "This session needs an unlocked Secret Service keyring and dbus-send. "
            "For a headless session, run python3 install/unix/keyring-session.py from common."
        )
    elif sys.platform == "darwin":
        if _mac_keyring_ready():
            return True
        diagnostic("Unlock the default macOS Keychain in this login session.")
    elif sys.platform == "win32":
        if _windows_keyring("dotfiles-keyring-check-" + uuid.uuid4().hex):
            return True
        diagnostic("Windows Credential Manager is unavailable in this logon session.")
    else:
        diagnostic("This platform has no supported OS keyring backend.")
    return False


def check_keyring_write():
    target = "dotfiles-keyring-check-" + uuid.uuid4().hex
    value = uuid.uuid4().hex
    if sys.platform.startswith("linux"):
        return _linux_round_trip(target, value)
    if sys.platform == "darwin":
        return _mac_round_trip(target, value)
    return _windows_keyring(target, value)
