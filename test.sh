#!/usr/bin/env bash

set -euo pipefail

basedir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
git -C "${basedir}" submodule update --init --recursive envtest

exec uv run "${basedir}/envtest/envtest.py" \
    --root "${basedir}" \
    --config "${basedir}/test.conf.yaml" \
    --config "${basedir}/test.unix.conf.yaml" \
    "$@"
