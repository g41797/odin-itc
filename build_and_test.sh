#!/usr/bin/env bash

set -euo pipefail

GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

OPTS=(none minimal size speed aggressive)

echo "${BLUE}Starting odin-mbox local CI...${NC}"

if ! command -v odin >/dev/null 2>&1; then
    echo "Error: odin compiler not found in PATH"
    exit 1
fi

for opt in "${OPTS[@]}"; do
    echo
    echo "${BLUE}--- opt: ${opt} ---${NC}"

    echo "  build root lib..."
    if [ "${opt}" = "none" ]; then
        odin build . -build-mode:lib -vet -strict-style -o:none -debug
    else
        odin build . -build-mode:lib -vet -strict-style -o:"${opt}"
    fi

    echo "  build examples..."
    if [ "${opt}" = "none" ]; then
        odin build ./examples/ -build-mode:lib -vet -strict-style -o:none -debug
    else
        odin build ./examples/ -build-mode:lib -vet -strict-style -o:"${opt}"
    fi

    echo "  test tests/..."
    if [ "${opt}" = "none" ]; then
        odin test ./tests/ -vet -strict-style -disallow-do -o:none -debug
    else
        odin test ./tests/ -vet -strict-style -disallow-do -o:"${opt}"
    fi

    echo "${GREEN}  pass: ${opt}${NC}"
done

echo
echo "${GREEN}ALL CHECKS PASSED${NC}"
