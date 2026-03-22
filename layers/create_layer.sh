#!/usr/bin/env bash
# Usage: ./create_layer.sh [N]
#   N - source layer number (default: highest existing layer)
# Creates layerN+1 from layerN and updates odin-itc.code-workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYERS_DIR="${SCRIPT_DIR}"
WORKSPACE_FILE="${SCRIPT_DIR}/../odin-itc.code-workspace"

# Determine source layer number
if [ $# -ge 1 ]; then
    SRC_N="$1"
else
    SRC_N=$(ls -d "${LAYERS_DIR}"/layer*/ 2>/dev/null \
        | grep -oP '(?<=layer)\d+' | sort -n | tail -1)
    if [ -z "${SRC_N}" ]; then
        echo "Error: no layers found in ${LAYERS_DIR}"
        exit 1
    fi
fi

DST_N=$((SRC_N + 1))
SRC_LAYER="${LAYERS_DIR}/layer${SRC_N}"
DST_LAYER="${LAYERS_DIR}/layer${DST_N}"

echo "Source : layer${SRC_N} (${SRC_LAYER})"
echo "Dest   : layer${DST_N} (${DST_LAYER})"

# Guards
if [ ! -d "${SRC_LAYER}" ]; then
    echo "Error: source layer not found: ${SRC_LAYER}"
    exit 1
fi
if [ -d "${DST_LAYER}" ]; then
    echo "Error: destination already exists: ${DST_LAYER}"
    exit 1
fi

# Copy layer
cp -r "${SRC_LAYER}" "${DST_LAYER}"

# Remove build artifacts from copy
find "${DST_LAYER}" -name "*.a"           -delete
find "${DST_LAYER}" -name "*.o"           -delete
find "${DST_LAYER}" -name "debug_current" -delete

# Update .code-workspace
python3 - <<EOF
import json, sys

with open('${WORKSPACE_FILE}', 'r') as f:
    ws = json.load(f)

new_folder = {"name": "layer${DST_N}", "path": "layers/layer${DST_N}"}

for folder in ws['folders']:
    if folder.get('path') == new_folder['path']:
        print("layer${DST_N} already in workspace file — skipped")
        sys.exit(0)

ws['folders'].append(new_folder)

with open('${WORKSPACE_FILE}', 'w') as f:
    json.dump(ws, f, indent=4)
    f.write('\n')

print("Updated odin-itc.code-workspace")
EOF

echo "Done. layer${DST_N} is ready."
