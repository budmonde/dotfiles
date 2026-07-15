#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
aliases_path="$script_dir/../../shell/aliases.sh"
capture_dir="$(mktemp -d)"
trap 'rm -rf "$capture_dir"' EXIT

cat > "$capture_dir/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CODEX_TEST_CAPTURE"
EOF
chmod +x "$capture_dir/codex"
export PATH="$capture_dir:$PATH"
export CODEX_PROFILE=cluster
export CODEX_TEST_CAPTURE="$capture_dir/args"
export IS_WSL=

source "$aliases_path"

assert_args() {
    local name="$1"
    shift
    local expected actual
    expected="$(printf '%s\n' "$@")"
    actual="$(cat "$CODEX_TEST_CAPTURE")"
    if [ "$actual" != "$expected" ]; then
        printf '%s\nexpected:\n%s\nactual:\n%s\n' "$name" "$expected" "$actual" >&2
        return 1
    fi
}

codex --cd /tmp/work
assert_args root --profile cluster --cd /tmp/work

codex resume --last
assert_args resume --profile cluster resume --last

codex exec summarize
assert_args exec --profile cluster exec summarize

codex review --base main
assert_args review --profile cluster review --base main

codex app-server --help
assert_args app-server app-server --help

codex doctor
assert_args doctor doctor

codex --version
assert_args version --version

codex --profile other resume
assert_args explicit-profile --profile other resume

printf '%s\n' 'Codex POSIX wrapper routing tests passed.'
