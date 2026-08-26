#!/bin/bash
chmod +x $GITHUB_WORKSPACE/scripts/diy-part1.sh
chmod +x $GITHUB_WORKSPACE/scripts/diy-part2.sh

# github源镜像加速，解决Action网络超时（进入 openwrt 目录操作）
sed -i 's#https://github.com#https://ghproxy.com/https://github.com#g' openwrt/feeds.conf.default

echo "==== diy‑part1.sh finished ===="
