#!/usr/bin/env bash

installer_note() {
    printf '%s\n' "$*" >&2
}

installer_online() {
    case "${DOTBOT_INSTALL_ONLINE:-1}" in
        0|false|False|no|No|off|Off) return 1 ;;
        *) return 0 ;;
    esac
}

installer_github_latest_version() {
    local repository="$1"
    installer_online || return 1
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsSL "https://api.github.com/repos/$repository/releases/latest" 2>/dev/null |
        sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"[:space:]]+)".*/\1/p' |
        head -1
}

installer_version_state() {
    local installed="$1"
    local latest="$2"
    if [ -n "$latest" ] && [ "$installed" != "$latest" ]; then
        printf 'update-available\n'
    else
        printf 'current\n'
    fi
}

installer_main() {
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        installer_note 'Expected: <status|apply|upgrade> [requested-version]'
        return 2
    fi

    local operation="$1"
    local requested_version="${2:-}"
    local function_name="installer_$operation"
    if ! declare -F "$function_name" >/dev/null; then
        installer_note "Unsupported installer operation: $operation"
        return 2
    fi

    local state
    if ! state="$($function_name "$requested_version")"; then
        return 1
    fi
    case "$state" in
        absent|blocked|current|drifted|unsupported|update-available)
            printf '%s\n' "$state"
            ;;
        *)
            installer_note "Installer returned an invalid state: $state"
            return 1
            ;;
    esac
}

installer_apt_state() {
    local package="$1"
    local requested_version="${2:-}"
    if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-query >/dev/null 2>&1; then
        printf 'unsupported\n'
        return
    fi

    local installed_version
    installed_version="$(dpkg-query -W -f='${Status} ${Version}' "$package" 2>/dev/null || true)"
    if [[ "$installed_version" != 'install ok installed '* ]]; then
        if ! apt-cache show "$package" >/dev/null 2>&1; then
            installer_note "APT package is unavailable from configured repositories: $package"
            printf 'unsupported\n'
            return
        fi
        printf 'absent\n'
        return
    fi

    installed_version="${installed_version##* }"
    if [ -n "$requested_version" ] && [ "$installed_version" != "$requested_version" ]; then
        printf 'drifted\n'
        return
    fi
    local candidate
    candidate="$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')"
    if [ -n "$candidate" ] && [ "$candidate" != '(none)' ] && \
        dpkg --compare-versions "$candidate" gt "$installed_version"; then
        printf 'update-available\n'
        return
    fi
    printf 'current\n'
}

installer_apt_update() {
    local state_root="${XDG_STATE_HOME:-$HOME/.local/state}/dotbot-install/apt"
    local stamp="$state_root/updated"
    if [ -f "$stamp" ] && find "$stamp" -mmin -60 -print -quit 2>/dev/null | grep -q .; then
        return
    fi
    mkdir -p "$state_root"
    sudo -n apt-get update >&2
    : > "$stamp"
}

installer_apt_mutate() {
    local package="$1"
    local requested_version="$2"
    local only_upgrade="$3"
    installer_apt_update

    local specification="$package"
    if [ -n "$requested_version" ]; then
        specification="$package=$requested_version"
    fi
    local arguments=(install -y)
    if [ "$only_upgrade" = 1 ] && [ -z "$requested_version" ]; then
        arguments+=(--only-upgrade)
    fi
    sudo -n apt-get "${arguments[@]}" "$specification" >&2
}

installer_apt_package() {
    local package="$1"
    shift

    installer_status() {
        installer_apt_state "$package" "$1"
    }

    installer_apply() {
        local requested_version="$1"
        local state
        state="$(installer_apt_state "$package" "$requested_version")"
        case "$state" in
            current|update-available|unsupported) printf '%s\n' "$state" ;;
            absent|drifted)
                installer_apt_mutate "$package" "$requested_version" 0
                installer_apt_state "$package" "$requested_version"
                ;;
            *) printf '%s\n' "$state" ;;
        esac
    }

    installer_upgrade() {
        local requested_version="$1"
        local state
        state="$(installer_apt_state "$package" "$requested_version")"
        if [ "$state" = unsupported ]; then
            printf 'unsupported\n'
            return
        fi
        installer_apt_mutate "$package" "$requested_version" "$([ "$state" = absent ] && printf 0 || printf 1)"
        installer_apt_state "$package" "$requested_version"
    }

    installer_main "$@"
}
