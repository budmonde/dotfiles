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

COMMON_CONFIG="install.conf.yaml"
UNIX_CONFIG="install.unix.conf.yaml"
DOTBOT_DIR="dotbot"
DOTBOT_BIN="bin/dotbot"
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${BASEDIR}"
git -C "${DOTBOT_DIR}" submodule sync --quiet --recursive
git submodule update --init --recursive "${DOTBOT_DIR}"

"${BASEDIR}/${DOTBOT_DIR}/${DOTBOT_BIN}" -d "${BASEDIR}" \
    -c "${COMMON_CONFIG}" "${UNIX_CONFIG}" \
    "${@}"
