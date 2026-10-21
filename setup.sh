#!/bin/sh
set -eu

UPSTREAM_URL='https://raw.githubusercontent.com/sryup/sift/main/sift'

usage() {
    cat <<'EOF'
Usage: sh setup.sh <install|update|uninstall> [--user | --prefix PATH]

Actions:
  install       Install the local sift file beside this script (offline).
  update        Download sift from sryup/sift main on GitHub over HTTPS.
  uninstall     Remove the installed sift executable only.

Destination:
  (default)     /usr/local/bin/sift; usually requires sudo.
  --user        $HOME/.local/bin/sift; run without sudo.
  --prefix PATH PATH/bin/sift; PATH must be absolute.

Use the same destination option for all three actions. Keep setup.sh for
future updates/removal. No background updates or shell-profile edits occur.
EOF
}

fail() {
    printf 'sift setup: %s\n' "$*" >&2
    exit 1
}

bad_args() {
    printf 'sift setup: %s\n' "$*" >&2
    printf 'Try: sh setup.sh --help\n' >&2
    exit 2
}

# Identify Sift without executing a downloaded or previously installed file.
# This is a format check, not a cryptographic signature.
file_version() {
    [ -f "$1" ] && [ -r "$1" ] || return 1
    LC_ALL=C awk '
        NR == 1 && $0 == "#!/bin/sh" { shell = 1 }
        /^VERSION="[0-9]+\.[0-9]+\.[0-9]+"$/ {
            versions++
            version = $0
            sub(/^VERSION="/, "", version)
            sub(/"$/, "", version)
        }
        /^show_version\(\) \{$/ { function_seen = 1 }
        /sift %s/ { name_seen = 1 }
        END {
            if (shell && versions == 1 && function_seen && name_seen)
                print version
            else
                exit 1
        }
    ' "$1"
}

not_older() {
    LC_ALL=C awk -v candidate="$1" -v current="$2" 'BEGIN {
        split(candidate, a, ".")
        split(current, b, ".")
        for (i = 1; i <= 3; i++) {
            if (a[i] + 0 > b[i] + 0) exit 0
            if (a[i] + 0 < b[i] + 0) exit 1
        }
        exit 0
    }'
}

action=${1:-}
case "$action" in
    -h|--help) usage; exit 0 ;;
    install|update|uninstall) shift ;;
    *) bad_args 'Choose install, update, or uninstall.' ;;
esac

prefix=/usr/local
destination_set=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --user)
            [ "$destination_set" -eq 0 ] || bad_args 'Choose only one destination.'
            [ -n "${HOME:-}" ] || bad_args 'HOME is not set; use --prefix PATH.'
            prefix="$HOME/.local"
            destination_set=1
            ;;
        --prefix|--prefix=*)
            [ "$destination_set" -eq 0 ] || bad_args 'Choose only one destination.'
            if [ "$1" = --prefix ]; then
                [ "$#" -ge 2 ] || bad_args '--prefix requires a path.'
                shift
                prefix=$1
            else
                prefix=${1#--prefix=}
            fi
            destination_set=1
            ;;
        -h|--help) usage; exit 0 ;;
        *) bad_args "Unrecognized argument: $1" ;;
    esac
    shift
done

case "$prefix" in
    /*) ;;
    *) bad_args 'The installation prefix must be an absolute path.' ;;
esac
while [ "${prefix%/}" != "$prefix" ]; do prefix=${prefix%/}; done
[ -n "$prefix" ] || bad_args 'The filesystem root cannot be an installation prefix.'
case "$prefix/" in
    */../*|*/./*) bad_args 'Use a prefix without dot or dot-dot path components.' ;;
esac

[ "$(uname -s)" = Linux ] || fail 'Linux is required.'
script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd) || fail 'Cannot find the setup directory.'
bin_dir="$prefix/bin"

if [ "$action" = install ]; then
    [ -f "$script_dir/sift" ] || fail 'The local sift file must be beside setup.sh.'
    mkdir -p -- "$bin_dir" || fail 'Cannot create the destination. Use sudo or --user as appropriate.'
elif [ ! -d "$bin_dir" ]; then
    if [ "$action" = uninstall ]; then
        printf 'Sift is not installed at %s/sift.\n' "$bin_dir"
        exit 0
    fi
    fail 'Sift is not installed at this destination. Run install first.'
fi

bin_dir=$(CDPATH='' cd -P "$bin_dir" && pwd) || fail 'Cannot resolve the destination.'
target="$bin_dir/sift"
[ "$target" != "$script_dir/sift" ] || fail 'The destination must not be the source checkout.'
[ -w "$bin_dir" ] || fail "Cannot write to $bin_dir. Use sudo or --user as appropriate."

temp_file=''
lock_dir="$bin_dir/.sift-setup.lock"
lock_owned=0
cleanup() {
    # Only remove our one staging file and our empty lock directory.
    case "$temp_file" in
        "$bin_dir"/.sift.??????) rm -f -- "$temp_file" ;;
    esac
    if [ "$lock_owned" -eq 1 ]; then rmdir -- "$lock_dir"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir -- "$lock_dir" 2>/dev/null || fail "Cannot acquire $lock_dir; another setup may be running."
lock_owned=1

[ ! -L "$target" ] || fail "Refusing to replace or remove a symlink: $target"
current_version=''
if [ -e "$target" ]; then
    current_version=$(file_version "$target") || fail "Not a recognized Sift executable: $target"
elif [ "$action" = update ]; then
    fail 'Sift is not installed at this destination. Run install first.'
fi

if [ "$action" = uninstall ]; then
    if [ -n "$current_version" ]; then
        rm -- "$target" || fail "Cannot remove $target."
        printf 'Uninstalled sift %s from %s. The source checkout is unchanged.\n' "$current_version" "$target"
    else
        printf 'Sift is not installed at %s.\n' "$target"
    fi
    exit 0
fi

temp_file=$(mktemp "$bin_dir/.sift.XXXXXX") || fail 'Cannot create a staging file.'
if [ "$action" = install ]; then
    cp -- "$script_dir/sift" "$temp_file" || fail 'Cannot copy the local sift file.'
else
    command -v curl >/dev/null 2>&1 || fail 'Updating requires curl and a working HTTPS certificate store.'
    printf 'Checking GitHub main for an update...\n'
    curl -q --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 60 \
        --output "$temp_file" "$UPSTREAM_URL" || fail 'Download failed; the installed Sift was not changed.'
fi

new_version=$(file_version "$temp_file") || fail 'The candidate is not a recognized Sift script; installation was not changed.'
sh -n "$temp_file" || fail 'The candidate has invalid shell syntax; installation was not changed.'
if [ -n "$current_version" ]; then
    not_older "$new_version" "$current_version" || fail "Refusing to downgrade sift $current_version to $new_version."
    if [ -x "$target" ] && cmp -s -- "$temp_file" "$target"; then
        printf 'Sift %s is already up to date at %s.\n' "$current_version" "$target"
        exit 0
    fi
fi

chmod 755 "$temp_file" || fail 'Cannot set executable permissions.'
# The staging file is on the destination filesystem. Rename only after all
# validation passes; -T prevents treating the target as a directory.
mv -fT -- "$temp_file" "$target" || fail 'Cannot replace the installed Sift.'
temp_file=''
printf 'Installed sift %s at %s.\n' "$new_version" "$target"
case ":${PATH:-}:" in
    *":$bin_dir:"*) ;;
    *) printf 'Add %s to PATH, or run sift using its full path.\n' "$bin_dir" ;;
esac
