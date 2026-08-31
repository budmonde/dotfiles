#!/usr/bin/env bash

set -e

# Fail fast on Git Bash / MSYS / Cygwin - use install.ps1 instead
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        echo "Error: This installer is not supported on Git Bash/MSYS/Cygwin."
        echo "Please use PowerShell and run: .\\install.ps1"
        exit 1
        ;;
esac

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${HOME}/.local/bin:${PATH}"

for python in python3 python; do
    if command -v "${python}" >/dev/null 2>&1; then
        exec "${python}" "${BASEDIR}/orchestrate.py" install "${@}"
    fi
done

echo "Error: Cannot find Python. Please install Python 3.8+ from https://python.org" >&2
exit 1
