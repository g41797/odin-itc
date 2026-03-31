#!/usr/bin/env bash
# preview_site.sh
# Generates odin-doc HTML then serves the full MkDocs site locally.
# Run from anywhere. Linux only.

set -e

TOOLS_DIR=$(dirname "$(readlink -f "$0")")
KITCHEN_DIR=$(dirname "$TOOLS_DIR")
ROOT_DIR=$(dirname "$KITCHEN_DIR")

if [ ! -f "$TOOLS_DIR/odin-doc" ]; then
    echo "Error: odin-doc binary not found in $TOOLS_DIR"
    echo "Run: bash kitchen/tools/get_odin_doc.sh"
    exit 1
fi

if ! command -v mkdocs >/dev/null 2>&1; then
    echo "Error: mkdocs not found in PATH"
    echo "Install: pip install mkdocs-material"
    exit 1
fi

echo "--- Generating API docs ---"
cd "$ROOT_DIR"
bash "$TOOLS_DIR/generate_apidocs.sh"

echo "--- Starting MkDocs site ---"
echo "Preview: http://localhost:8000"
echo "(Press Ctrl+C to stop)"
cd "$KITCHEN_DIR"
mkdocs serve -f mkdocs.yml
