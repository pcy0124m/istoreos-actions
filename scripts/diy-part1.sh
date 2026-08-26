#!/bin/bash
chmod +x $GITHUB_WORKSPACE/scripts/diy-part1.sh
chmod +x $GITHUB_WORKSPACE/scripts/diy-part2.sh

# github源镜像加速，解决Action网络超时（进入 openwrt 目录操作）
sed -i 's#https://github.com#https://ghproxy.com/https://github.com#g' openwrt/feeds.conf.default

# 添加 iStoreOS 第三方软件源到 feeds.conf.default（替代 src-include，兼容性更好）
cat >> openwrt/feeds.conf.default << EOF
src-git third_party https://github.com/linkease/istore-packages.git;main
src-git diskman https://github.com/jjm2473/luci-app-diskman.git;dev
src-git oaf https://github.com/jjm2473/OpenAppFilter.git;dev
src-git linkease_nas https://github.com/linkease/nas-packages.git;master
src-git linkease_nas_luci https://github.com/linkease/nas-packages-luci.git;main
# jjm2473_apps 暂时移除（luci-lib-mac-vendor 的 Makefile 有问题，上游待修复）
# src-git jjm2473_apps https://github.com/jjm2473/openwrt-apps.git;main
EOF

echo "==== diy‑part1.sh finished ===="
