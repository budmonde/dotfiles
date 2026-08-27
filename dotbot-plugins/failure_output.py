import os
import platform
import subprocess
import sys

from dotbot.plugins import shell as dotbot_shell


_original_shell_command = dotbot_shell.shell_command


def _write_output(stream, output):
    if not output:
        return
    buffer = getattr(stream, "buffer", None)
    if buffer is not None:
        buffer.write(output)
        if not output.endswith(b"\n"):
            buffer.write(b"\n")
        buffer.flush()
        return
    text = output.decode(errors="replace")
    stream.write(text)
    if not text.endswith("\n"):
        stream.write("\n")
    stream.flush()


def shell_command(
    command,
    cwd=None,
    *,
    enable_stdin=False,
    enable_stdout=False,
    enable_stderr=False,
):
    if enable_stdout or enable_stderr:
        return _original_shell_command(
            command,
            cwd,
            enable_stdin=enable_stdin,
            enable_stdout=enable_stdout,
            enable_stderr=enable_stderr,
        )

    executable = None if platform.system() == "Windows" else os.environ.get("SHELL")
    with open(os.devnull) as devnull:
        result = subprocess.run(
            command,
            shell=True,
            executable=executable,
            stdin=None if enable_stdin else devnull,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd,
            check=False,
        )
    if result.returncode:
        _write_output(sys.stdout, result.stdout)
        _write_output(sys.stderr, result.stderr)
    return result.returncode


dotbot_shell.shell_command = shell_command
