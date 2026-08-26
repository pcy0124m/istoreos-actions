#!/bin/bash
BRANCH="$1"
TARGET="$2"
chmod +x $GITHUB_WORKSPACE/scripts/diy-part1.sh
chmod +x $GITHUB_WORKSPACE/scripts/diy-part2.sh

echo "diy‑part2.sh run, branch:${BRANCH}, target:${TARGET}"
