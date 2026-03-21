#!/bin/bash
# Usage: build_test.sh <odin> <package_path> <output_path>
# Compiles odin test binary and keeps it after odin test deletes it.
set -e

ODIN="$1"
PACKAGE="$2"
OUTPATH="$3"
KEEPPATH="${OUTPATH}.keep"

# Background watcher: hardlink the binary the moment it appears
(
    while [ ! -f "$OUTPATH" ]; do sleep 0.02; done
    ln -f "$OUTPATH" "$KEEPPATH" 2>/dev/null || cp -f "$OUTPATH" "$KEEPPATH"
) &
WATCHER=$!

# Compile and run tests (odin deletes the binary after running)
"$ODIN" test "$PACKAGE" -debug -o:none -out:"$OUTPATH"
STATUS=$?

wait $WATCHER 2>/dev/null || true

# Restore binary if odin deleted it
if [ ! -f "$OUTPATH" ] && [ -f "$KEEPPATH" ]; then
    mv "$KEEPPATH" "$OUTPATH"
else
    rm -f "$KEEPPATH"
fi

exit $STATUS
