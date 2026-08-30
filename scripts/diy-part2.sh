#!/bin/bash
BRANCH="$1"
TARGET="$2"
chmod +x $GITHUB_WORKSPACE/scripts/diy-part1.sh
chmod +x $GITHUB_WORKSPACE/scripts/diy-part2.sh || true

echo "diy-part2.sh run, branch:${BRANCH}, target:${TARGET}"
# 不做任何网络配置修改，让 iStoreOS 默认 defconfig 处理
