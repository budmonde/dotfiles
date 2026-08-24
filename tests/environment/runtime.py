from dataclasses import dataclass
from typing import Optional

from environment.configuration import EnvironmentConfiguration


@dataclass(frozen=True)
class EnvironmentRuntime:
    configuration: EnvironmentConfiguration
    live: bool


_runtime: Optional[EnvironmentRuntime] = None


def configure_runtime(runtime: EnvironmentRuntime) -> None:
    global _runtime
    _runtime = runtime


def get_runtime() -> EnvironmentRuntime:
    if _runtime is None:
        raise RuntimeError("environment runtime has not been configured")
    return _runtime
