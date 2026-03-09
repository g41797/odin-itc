#!/usr/bin/env bash

# Exit on error, undefined variable, or failed pipe
set -euo pipefail

# Colors for output
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

# Odin optimization modes
OPTS=(none minimal size speed aggressive)

echo "${BLUE}Starting Odin Mailbox Local CI...${NC}"

# Ensure Odin compiler exists
if ! command -v odin >/dev/null 2>&1; then
    echo "Error: odin compiler not found in PATH"
    exit 1
fi

for opt in "${OPTS[@]}"; do
    echo
    echo "${BLUE}Testing configuration: -o:${opt}${NC}"

    echo "Running build check..."
    odin build . \
        -vet \
        -strict-style \
        # -disallow-do \
        -o:${opt}

    echo "Running tests..."
    odin test . \
        -vet \
        -strict-style \
        -disallow-do \
        -o:${opt}

    echo "${GREEN}Pass: -o:${opt}${NC}"
done

echo
echo "${GREEN}ALL LOCAL CHECKS PASSED${NC}"
