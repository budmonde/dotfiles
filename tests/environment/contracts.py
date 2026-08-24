import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

from environment.configuration import CommandCheck, FileCheck, LinkCheck, RepositoryCheck


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class RepositoryState:
    worktree_status: str
    ahead: Optional[int]
    behind: Optional[int]


def common_root() -> Path:
    return Path(__file__).resolve().parents[2]


def source_path(contract: LinkCheck) -> Path:
    return (common_root() / contract.source).resolve()


def resolved_link_target(contract: LinkCheck) -> Optional[Path]:
    installed_path = expand_path(contract.target)
    if not installed_path.exists():
        return None
    return installed_path.resolve()


def required_file_path(contract: FileCheck) -> Path:
    return expand_path(contract.path)


def path_candidates(command: str) -> Tuple[Path, ...]:
    selected = shutil.which(command)
    candidates = []
    if selected:
        candidates.append(Path(selected).resolve())

    command_path = Path(command)
    if command_path.parent != Path("."):
        _append_candidate(candidates, command_path)
        return tuple(candidates)

    for entry in os.environ.get("PATH", "").split(os.pathsep):
        if not entry:
            continue
        for suffix in _command_suffixes(command):
            _append_candidate(candidates, Path(entry) / "{}{}".format(command, suffix))
    return tuple(candidates)


def command_result(contract: CommandCheck) -> CommandResult:
    try:
        result = subprocess.run(
            contract.argv,
            cwd=str(common_root()),
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=contract.timeout_seconds,
            check=False,
        )
    except OSError as error:
        return CommandResult(returncode=-1, stdout="", stderr=str(error))
    except subprocess.TimeoutExpired:
        return CommandResult(returncode=-1, stdout="", stderr="command timed out")
    return CommandResult(
        returncode=result.returncode,
        stdout=result.stdout,
        stderr=result.stderr,
    )


def repository_state(contract: RepositoryCheck) -> RepositoryState:
    repository = (common_root() / contract.path).resolve()
    status = _git(repository, "status", "--porcelain")
    if status.returncode != 0:
        return RepositoryState(
            worktree_status="git status failed",
            ahead=None,
            behind=None,
        )

    if not contract.synchronized:
        return RepositoryState(
            worktree_status=status.stdout.strip(),
            ahead=None,
            behind=None,
        )

    divergence = _git(repository, "rev-list", "--left-right", "--count", "@{upstream}...HEAD")
    counts = divergence.stdout.split()
    if divergence.returncode != 0 or len(counts) != 2 or not all(item.isdigit() for item in counts):
        return RepositoryState(
            worktree_status=status.stdout.strip(),
            ahead=None,
            behind=None,
        )
    return RepositoryState(
        worktree_status=status.stdout.strip(),
        behind=int(counts[0]),
        ahead=int(counts[1]),
    )


def expand_path(value: str) -> Path:
    return Path(os.path.expandvars(value)).expanduser()


def selected_paths(paths: Tuple[str, ...]) -> Tuple[Path, ...]:
    return tuple(expand_path(path).resolve() for path in paths)


def _append_candidate(candidates: List[Path], path: Path) -> None:
    if not path.is_file() or not os.access(str(path), os.X_OK):
        return
    resolved = path.resolve()
    if resolved not in candidates:
        candidates.append(resolved)


def _command_suffixes(command: str) -> Tuple[str, ...]:
    if os.name != "nt" or Path(command).suffix:
        return ("",)
    extensions = os.environ.get("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";")
    return tuple(extension.lower() for extension in extensions)


def _git(repository: Path, *arguments: str) -> CommandResult:
    try:
        result = subprocess.run(
            ("git",) + arguments,
            cwd=str(repository),
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError as error:
        return CommandResult(returncode=-1, stdout="", stderr=str(error))
    return CommandResult(
        returncode=result.returncode,
        stdout=result.stdout,
        stderr=result.stderr,
    )
