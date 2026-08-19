#!/bin/bash
# Regenerates docs/tools-reference.md from every script's own --help
# output, so the reference can't drift from what the scripts actually do.
# Run this after changing any script's --help text.
#
# Not a standalone tool itself — excluded from its own output.
set -e

SCRIPTPATH=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(dirname "$SCRIPTPATH")
OUT="$REPO_ROOT/docs/tools-reference.md"

{
    echo "# Tools reference"
    echo
    echo "Generated from each script's own \`--help\` output by"
    echo '`bin/_generate-tools-reference.sh` — do not hand-edit; run that'
    echo "script again after changing a script's \`--help\` text."
    echo
    echo "\`setup\` is at the repo root; everything else is on \`PATH\` after"
    echo "running it (see \`README.md\`)."
    echo

    for script in "$REPO_ROOT/setup" "$REPO_ROOT"/bin/*; do
        name=$(basename "$script")
        case "$name" in
            _*) continue ;;
        esac
        [ -f "$script" ] || continue

        echo "## \`$name\`"
        echo
        echo '```'
        bash "$script" --help
        echo '```'
        echo
    done
} > "$OUT"

echo "Wrote $OUT"
