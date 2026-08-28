#!/bin/bash
chmod +x $GITHUB_WORKSPACE/scripts/diy-part1.sh
chmod +x $GITHUB_WORKSPACE/scripts/diy-part2.sh

# 注意：GitHub Actions runner 在美国，不需要 ghproxy 代理
# ghproxy 反而可能返回错误缓存导致包架构不兼容
# 原来的：
# sed -i 's#https://github.com#https://ghproxy.com/https://github.com#g' openwrt/feeds.conf.default

# 添加 iStoreOS 第三方软件源到 feeds.conf.default
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
