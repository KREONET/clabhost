#!/bin/sh
# Install the extension set into the editor's extension directory, then exit.
#
# Something has to run --install-extension: an editor never installs from a list
# on its own. A .vscode/extensions.json only makes VS Code *offer* the list, and
# the offer has to be clicked. This is that step. install.sh runs it as the
# editor's account after installing code-server, and you can run it again by
# hand at any time -- it is safe to repeat.
#
# It only installs what is missing. That matters more than it looks: asking the
# marketplace about fourteen extensions that are already on disk is a slow no-op
# online and a slow failure on a host with no egress.
#
# The extension directory sits under DATA_DIR, not next to the binary, so
# upgrading code-server does not mean reinstalling extensions.
#
# Environment
#   EXT_DIR     where to install (required)
#   EXT_LIST    the extension list (default <script dir>/extensions.txt)
#   EXT_SET     minimal | network | full
#   EXT_UPDATE  set to 1 to reinstall everything and pick up new versions
#   VSIX_DIR    drop .vsix files here and they are installed before the
#               marketplace is consulted -- see docs/airgap.ko.md
#   CODE_SERVER code-server binary (default: whatever is on PATH)
set -eu

: "${EXT_DIR:?EXT_DIR must be set}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EXT_LIST="${EXT_LIST:-$HERE/extensions.txt}"
VSIX_DIR="${VSIX_DIR:-$HERE/vsix}"
EXT_SET="${EXT_SET:-full}"
EXT_UPDATE="${EXT_UPDATE:-0}"
CODE_SERVER="${CODE_SERVER:-code-server}"

mkdir -p "$EXT_DIR"

WANT=$(awk -v want="$EXT_SET" '
    /^# --- SET / { cur = $4; next }
    /^#/ || /^$/  { next }
    {
        if (want == "minimal" && cur != "minimal") next
        if (want == "network" && cur == "full")    next
        print
    }' "$EXT_LIST")

if [ -z "$WANT" ]; then
    echo "no extensions match set '$EXT_SET'" >&2
    exit 1
fi

# Extensions unpack to <publisher>.<name>-<version>[-<platform>], lowercased.
# The manifest in extensions.json would also answer this, but a directory glob
# needs no JSON parser and stays right when an extension is removed by hand.
installed() {
    id=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    for dir in "$EXT_DIR/$id-"*; do
        [ -d "$dir" ] && return 0
    done
    return 1
}

failed=""

# Local .vsix files, installed before the marketplace is consulted. This is the
# whole air-gap story for extensions: drop the files in and the host needs no
# egress at all.
#
# Every file present is installed, not just the ones this set asks for. An
# offline install resolves no dependencies -- it reports success and silently
# skips them -- so the only way a dependency arrives is that someone dropped it
# in as well, and second-guessing that here would throw it away.
if [ -d "$VSIX_DIR" ]; then
    for vsix in "$VSIX_DIR"/*.vsix; do
        [ -f "$vsix" ] || continue
        # publisher.name-1.2.3.vsix, and @platform for the ones with per-arch
        # builds: charliermarsh.ruff-2026.78.0@linux-x64.vsix.
        id=$(basename "$vsix" | sed 's/\.vsix$//; s/@.*$//; s/-[0-9][0-9.]*$//')
        if [ "$EXT_UPDATE" != 1 ] && installed "$id"; then
            echo "  have    $id"
            continue
        fi
        # --force always: the file is on disk because someone put it there, and
        # that is a more explicit choice than whatever version is installed.
        if "$CODE_SERVER" --extensions-dir "$EXT_DIR" \
                       --install-extension "$vsix" --force >/dev/null 2>&1; then
            echo "  ok      $id  (vsix)"
        else
            echo "  FAILED  $id  (vsix)"
            failed="$failed $id"
        fi
    done
fi

todo=""
for ext in $WANT; do
    if [ "$EXT_UPDATE" = 1 ] || ! installed "$ext"; then
        todo="$todo $ext"
    fi
done

if [ -z "$todo" ]; then
    echo "extension set '$EXT_SET' is already installed; nothing to do"
else
    n=$(printf '%s\n' $todo | wc -l | tr -d ' ')
    echo "extension set '$EXT_SET': installing $n"
    force=""
    [ "$EXT_UPDATE" = 1 ] && force="--force"
    for ext in $todo; do
        # shellcheck disable=SC2086
        if "$CODE_SERVER" --extensions-dir "$EXT_DIR" --install-extension "$ext" $force >/dev/null 2>&1; then
            echo "  ok      $ext"
        else
            echo "  FAILED  $ext"
            failed="$failed $ext"
        fi
    done
fi

# An unreachable marketplace must not stop the editor from starting -- an editor
# without extensions is still an editor. `install.sh check` reports this file so
# a partial install does not go unnoticed. On an air-gapped host the list is the
# answer to "which .vsix did I forget".
if [ -n "$failed" ]; then
    printf '%s\n' $failed > "$EXT_DIR/.install-failures"
    echo "could not install:$failed" >&2
else
    rm -f "$EXT_DIR/.install-failures"
fi

# Hand the list to the editor as workspace recommendations too. It changes
# nothing when seeding worked, and gives a one-click retry when it did not --
# which is the only recovery path a user has on a host that was offline.
{
    echo '{'
    echo '  "recommendations": ['
    printf '%s\n' $WANT | sed 's/.*/    "&",/' | sed '$ s/,$//'
    echo '  ]'
    echo '}'
} > "$EXT_DIR/.recommendations.json"
