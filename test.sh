#!/usr/bin/env bash

set -euo pipefail

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        echo "Error: This test launcher is not supported on Git Bash/MSYS/Cygwin."
        echo "Please use PowerShell and run: .\\test.ps1"
        exit 1
        ;;
esac

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${HOME}/.local/bin:${PATH}"

for python in python3 python; do
    if command -v "${python}" >/dev/null 2>&1; then
        exec "${python}" "${BASEDIR}/orchestrate.py" test "${@}"
    fi
done

echo "Error: Cannot find Python. Please install Python 3.8+ from https://python.org" >&2
exit 1
