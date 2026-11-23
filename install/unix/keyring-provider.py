import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


repo_root = Path(
    os.environ.get("DOTBOT_INSTALL_REPO_ROOT", Path(__file__).resolve().parents[2])
)
sys.path.insert(0, str(repo_root / "install/lib/python"))

from lifecycle import InstallerError, diagnostic, main
from lifecycle.keyring import (
    ubuntu_noble_amd64,
    linux_keyring_command,
    linux_keyring_prefix,
    linux_keyring_locked,
)


NOBLE_KEYRING_PACKAGES = (
    "gnome-keyring",
    "libgck-1-0",
    "libgcr-base-3-1",
    "libsecret-1-0",
    "libsecret-common",
    "libsecret-tools",
)


def _linux_tools_present():
    return bool(
        shutil.which("dbus-send")
        and linux_keyring_command("secret-tool")[0]
        and (
            linux_keyring_locked() is not None
            or (shutil.which("dbus-run-session") and linux_keyring_command("gnome-keyring-daemon")[0])
        )
    )


def _install_linux_tools(operation):
    if not shutil.which("apt-get"):
        diagnostic("Install Linux Secret Service and libsecret-tools with the system package manager.")
        return False

    environment = {**os.environ, "DOTBOT_INSTALL_REPO_ROOT": str(repo_root)}
    for package in ("dbus-daemon", "dbus-bin", "gnome-keyring", "libsecret-tools"):
        result = subprocess.run(
            [str(repo_root / "install/unix/apt-package"), package, operation],
            capture_output=True,
            stdin=subprocess.DEVNULL,
            text=True,
            env=environment,
        )
        state = result.stdout.strip()
        if result.stderr:
            diagnostic(result.stderr.rstrip())
        if result.returncode != 0 or state not in {"current", "update-available"}:
            diagnostic("Could not prepare the Linux keyring package {}.".format(package))
            return False
    return True


def _install_userspace_tools():
    import pwd

    signing_key = Path("/usr/share/keyrings/ubuntu-archive-keyring.gpg")
    if not (
        ubuntu_noble_amd64()
        and signing_key.is_file()
        and all(shutil.which(name) for name in (
            "apt-get", "dpkg-deb", "dbus-send", "dbus-run-session"
        ))
    ):
        diagnostic(
            "Userspace provisioning requires Ubuntu 24.04 amd64 with its archive keyring, "
            "APT, dpkg-deb, and the D-Bus tools."
        )
        return False

    prefix = linux_keyring_prefix()
    if prefix.exists() or prefix.is_symlink():
        diagnostic("Userspace keyring tools already exist but are incomplete at {}.".format(prefix))
        return False
    prefix.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=prefix.parent, prefix=".install-") as directory:
        work = Path(directory)
        for name in ("lists/partial", "archives/partial", "payload"):
            (work / name).mkdir(parents=True)
        sources = work / "sources.list"
        sources.write_text(
            "".join(
                "deb [signed-by={}] https://archive.ubuntu.com/ubuntu {} main universe\n".format(
                    signing_key, suite
                )
                for suite in ("noble", "noble-updates", "noble-security")
            ),
            encoding="utf-8",
        )
        apt = [
            "apt-get",
            "-qq",
            "-o", "Dir::Etc::sourcelist=" + str(sources),
            "-o", "Dir::Etc::sourceparts=-",
            "-o", "Dir::State::Lists=" + str(work / "lists"),
            "-o", "Dir::Cache::archives=" + str(work / "archives"),
            "-o", "APT::Sandbox::User=" + pwd.getpwuid(os.getuid()).pw_name,
        ]
        for command in (apt + ["update"], apt + ["download", *NOBLE_KEYRING_PACKAGES]):
            subprocess.run(command, cwd=work, stdin=subprocess.DEVNULL, stdout=sys.stderr, check=True)
        payload = work / "payload"
        for package in sorted(work.glob("*.deb")):
            subprocess.run(["dpkg-deb", "-x", str(package), str(payload)], check=True)
        libraries = sorted((payload / "usr/lib").glob("*-linux-*"))
        environment = {**os.environ, "LD_LIBRARY_PATH": os.pathsep.join(map(str, libraries))}
        for executable, flag, expected in (
            ("gnome-keyring-daemon", "--version", 0),
            ("secret-tool", "--help", 2),
        ):
            if subprocess.run(
                [str(payload / "usr/bin" / executable), flag],
                env=environment,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
            ).returncode != expected:
                diagnostic("The userspace keyring package {} cannot run on this host.".format(executable))
                return False
        try:
            payload.rename(prefix)
        except OSError:
            if not _linux_tools_present():
                raise
    diagnostic("Installed userspace GNOME Keyring at {}.".format(prefix))
    return True


def provision_keyring(operation, requested_version, scope):
    if requested_version:
        raise InstallerError("The OS keyring provider does not accept a requested version.")
    if _linux_tools_present():
        return "current"
    if operation == "status":
        diagnostic("Linux keyring provider or client tools are missing.")
        return "blocked"
    try:
        if scope == "system":
            installed = _install_linux_tools(operation)
        else:
            installed = _install_userspace_tools()
    except subprocess.CalledProcessError:
        diagnostic("Unable to install the Linux keyring packages.")
        return "blocked"
    return "current" if installed and _linux_tools_present() else "blocked"


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if not arguments or arguments[0] not in {"system", "userspace"}:
        diagnostic("Expected: <system|userspace> <status|apply|upgrade>")
        raise SystemExit(2)
    scope, *lifecycle_arguments = arguments
    raise SystemExit(main(
        lambda operation, version: provision_keyring(operation, version, scope),
        lifecycle_arguments,
    ))
