import os
import re
import shutil
from pathlib import Path

from .core import InstallerError, capture, diagnostic, report


MACHINE_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")


def _machine_id(service_name):
    value = os.environ.get("DOTFILES_MACHINE_ID", "").strip()
    if not value:
        diagnostic(
            "Set DOTFILES_MACHINE_ID before managing the {} SSH key.".format(
                service_name
            )
        )
        return None
    if MACHINE_ID_PATTERN.fullmatch(value) is None:
        diagnostic(
            "DOTFILES_MACHINE_ID must be lowercase and contain only letters, digits, dots, underscores, or hyphens."
        )
        return None
    return value


def _key_paths(key_filename):
    private_key = Path.home() / ".ssh" / "git" / key_filename
    return private_key, Path(str(private_key) + ".pub")


def _public_identity(value):
    fields = value.strip().split()
    return tuple(fields[:2]) if len(fields) >= 2 else None


def _registered(keys, identity, remote_key_usable):
    return any(
        _public_identity(str(item.get("key", ""))) == identity
        and (remote_key_usable is None or remote_key_usable(item))
        for item in keys
    )


def _local_key(service_name, private_key, public_key):
    private_exists = private_key.is_file()
    public_exists = public_key.is_file()
    if not private_exists and not public_exists:
        return "absent", None
    if not private_exists or not public_exists:
        diagnostic("The managed {} SSH key pair is incomplete.".format(service_name))
        return "drifted", None

    try:
        public_identity = _public_identity(public_key.read_text(encoding="utf-8"))
    except OSError as error:
        diagnostic(
            "Unable to read the managed {} public key: {}".format(
                service_name, error
            )
        )
        return "blocked", None

    if public_identity is None or public_identity[0] != "ssh-ed25519":
        diagnostic(
            "The managed {} public key is not a valid Ed25519 key.".format(
                service_name
            )
        )
        return "drifted", None

    derived = capture(["ssh-keygen", "-y", "-f", str(private_key)])
    if derived.returncode != 0 or _public_identity(derived.stdout) != public_identity:
        report(derived)
        diagnostic(
            "The managed {} private and public keys do not match.".format(
                service_name
            )
        )
        return "drifted", None
    _warn_if_private_key_exposed(service_name, private_key)
    return "current", public_identity


def _private_key_exposed(private_key):
    if os.name != "nt":
        try:
            return bool(private_key.stat().st_mode & 0o077)
        except OSError:
            return None

    powershell = shutil.which("pwsh") or shutil.which("powershell")
    if powershell is None:
        return None
    script = (
        "$acl=Get-Acl -LiteralPath $args[0];"
        "$owner=(New-Object System.Security.Principal.NTAccount($acl.Owner))."
        "Translate([System.Security.Principal.SecurityIdentifier]).Value;"
        "$safe=@($owner,'S-1-5-18','S-1-5-32-544');"
        "$exposed=$false;"
        "foreach($rule in $acl.Access){"
        "try{$sid=$rule.IdentityReference.Translate("
        "[System.Security.Principal.SecurityIdentifier]).Value}catch{continue};"
        "if($rule.AccessControlType -eq "
        "[System.Security.AccessControl.AccessControlType]::Allow -and "
        "$safe -notcontains $sid -and ([int]$rule.FileSystemRights -band 1)){"
        "$exposed=$true;break}};"
        "if($exposed){'exposed'}else{'protected'}"
    )
    result = capture(
        [
            powershell,
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            script,
            str(private_key),
        ]
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip().splitlines()[-1:] == ["exposed"]


def _warn_if_private_key_exposed(service_name, private_key):
    exposed = _private_key_exposed(private_key)
    if exposed is True:
        diagnostic(
            "Warning: the managed {} private key at {} has broader-than-owner access; permissions were not changed.".format(
                service_name, private_key
            )
        )
    elif exposed is None:
        diagnostic(
            "Warning: unable to inspect access controls for the managed {} private key at {}; permissions were not changed.".format(
                service_name, private_key
            )
        )


def _observe(
    service_name,
    private_key,
    public_key,
    list_remote_keys,
    remote_key_usable,
):
    state, identity = _local_key(service_name, private_key, public_key)
    if state != "current":
        return state, identity, []

    keys = list_remote_keys()
    if keys is None:
        return "blocked", identity, []
    registered = _registered(keys, identity, remote_key_usable)
    return ("current" if registered else "drifted"), identity, keys


def _generate_key(private_key, title):
    private_key.parent.mkdir(parents=True, exist_ok=True)
    if os.name != "nt":
        os.chmod(private_key.parent, 0o700)
    result = capture(
        [
            "ssh-keygen",
            "-q",
            "-t",
            "ed25519",
            "-N",
            "",
            "-C",
            title,
            "-f",
            str(private_key),
        ]
    )
    if result.returncode != 0:
        report(result)
        return False
    if os.name != "nt":
        os.chmod(private_key, 0o600)
        os.chmod(Path(str(private_key) + ".pub"), 0o644)
    return True


def _replacement_key_paths(private_key):
    replacement_private = Path(str(private_key) + ".replacement")
    return replacement_private, Path(str(replacement_private) + ".pub")


def _remove_key_pair(private_key, public_key):
    for path in (private_key, public_key):
        if path.exists():
            path.unlink()


def _activate_replacement(
    private_key,
    public_key,
    replacement_private,
    replacement_public,
):
    backup_private = Path(str(private_key) + ".previous")
    backup_public = Path(str(public_key) + ".previous")
    if backup_private.exists() or backup_public.exists():
        diagnostic("A previous managed SSH key backup requires manual review.")
        return False

    try:
        os.replace(private_key, backup_private)
        os.replace(public_key, backup_public)
        os.replace(replacement_private, private_key)
        os.replace(replacement_public, public_key)
    except OSError as error:
        if backup_private.exists():
            os.replace(backup_private, private_key)
        if backup_public.exists():
            os.replace(backup_public, public_key)
        diagnostic("Unable to activate the replacement SSH key: {}".format(error))
        return False

    try:
        backup_private.unlink()
        backup_public.unlink()
    except OSError as error:
        diagnostic("Unable to remove the previous SSH key backup: {}".format(error))
        return False
    return True


def _verify_key(private_key, ssh_target, authentication_text):
    result = capture(
        [
            "ssh",
            "-T",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            "-o",
            "ConnectionAttempts=1",
            "-o",
            "StrictHostKeyChecking=accept-new",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "PermitLocalCommand=no",
            "-i",
            str(private_key),
            ssh_target,
        ]
    )
    if authentication_text.lower() in "\n".join(
        (result.stdout, result.stderr)
    ).lower():
        return True
    report(result)
    return False


def _delete_stale_keys(keys, identity, title, delete_remote_key):
    for item in keys:
        if item.get("title") != title:
            continue
        if _public_identity(str(item.get("key", ""))) == identity:
            continue
        if "id" not in item or not delete_remote_key(item["id"]):
            return False
    return True


def _rotate_unusable_key(
    service_name,
    private_key,
    public_key,
    title,
    keys,
    identity,
    ssh_target,
    authentication_text,
    list_remote_keys,
    upload_remote_key,
    delete_remote_key,
    remote_key_usable,
):
    matching_keys = [
        item
        for item in keys
        if _public_identity(str(item.get("key", ""))) == identity
    ]
    if not matching_keys or remote_key_usable is None:
        return None

    replacement_private, replacement_public = _replacement_key_paths(private_key)
    if replacement_private.exists() or replacement_public.exists():
        diagnostic("A pending managed SSH key replacement requires manual review.")
        return "blocked"
    if not _generate_key(replacement_private, title):
        return "blocked"

    try:
        local_state, replacement_identity = _local_key(
            service_name, replacement_private, replacement_public
        )
        if local_state != "current":
            return local_state
        if not upload_remote_key(replacement_public, title):
            return "blocked"
        if not _verify_key(
            replacement_private, ssh_target, authentication_text
        ):
            diagnostic(
                "The replacement {} SSH key did not pass authentication verification.".format(
                    service_name
                )
            )
            return "blocked"
        if not _activate_replacement(
            private_key,
            public_key,
            replacement_private,
            replacement_public,
        ):
            return "blocked"
        for item in matching_keys:
            if "id" not in item or not delete_remote_key(item["id"]):
                return "drifted"
        final_state, _, _ = _observe(
            service_name,
            private_key,
            public_key,
            list_remote_keys,
            remote_key_usable,
        )
        return final_state
    finally:
        _remove_key_pair(replacement_private, replacement_public)


def managed_ssh_key(
    operation,
    requested_version,
    *,
    service_name,
    key_filename,
    required_commands,
    ssh_target,
    authentication_text,
    list_remote_keys,
    upload_remote_key,
    delete_remote_key,
    remote_key_usable=None,
):
    if requested_version:
        raise InstallerError(
            "{} SSH key management does not accept a requested version.".format(
                service_name
            )
        )

    machine_id = _machine_id(service_name)
    missing = [name for name in required_commands if shutil.which(name) is None]
    if machine_id is None or missing:
        if missing:
            diagnostic("Missing required commands: {}".format(", ".join(missing)))
        return "blocked"

    private_key, public_key = _key_paths(key_filename)
    title = "dotfiles:{}".format(machine_id)
    state, identity, keys = _observe(
        service_name,
        private_key,
        public_key,
        list_remote_keys,
        remote_key_usable,
    )
    if operation == "status" or state == "blocked":
        return state
    if state == "drifted" and identity is None:
        return state

    if state == "absent":
        if not _generate_key(private_key, title):
            return "blocked"
        local_state, identity = _local_key(service_name, private_key, public_key)
        if local_state != "current":
            return local_state
        keys = list_remote_keys()
        if keys is None:
            return "blocked"

    registered = _registered(keys, identity, remote_key_usable)
    if not registered:
        rotated_state = _rotate_unusable_key(
            service_name,
            private_key,
            public_key,
            title,
            keys,
            identity,
            ssh_target,
            authentication_text,
            list_remote_keys,
            upload_remote_key,
            delete_remote_key,
            remote_key_usable,
        )
        if rotated_state is not None:
            return rotated_state
    if not registered and not upload_remote_key(public_key, title):
        return "blocked"
    if not _verify_key(private_key, ssh_target, authentication_text):
        diagnostic(
            "The managed {} SSH key did not pass authentication verification.".format(
                service_name
            )
        )
        return "blocked"
    if operation == "upgrade" and not _delete_stale_keys(
        keys, identity, title, delete_remote_key
    ):
        return "drifted"

    final_state, _, _ = _observe(
        service_name,
        private_key,
        public_key,
        list_remote_keys,
        remote_key_usable,
    )
    return final_state
