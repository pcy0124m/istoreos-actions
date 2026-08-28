#!/bin/bash
chmod +x $GITHUB_WORKSPACE/scripts/diy-part1.sh
chmod +x $GITHUB_WORKSPACE/scripts/diy-part2.sh

# 注意：GitHub Actions runner 在美国，不需要 ghproxy 代理
# ghproxy 反而可能返回错误缓存导致包架构不兼容

# ============================================================
# 添加京东云 RE-SP-01B 设备定义（iStoreOS 官方源码没有此设备）
# ============================================================
MT7621_MK="openwrt/target/linux/ramips/image/mt7621.mk"
if ! grep -q "jdcloud_re-sp-01b" "$MT7621_MK" 2>/dev/null; then
  echo "===== 添加 jdcloud_re-sp-01b 设备定义 ====="
  cat >> "$MT7621_MK" << 'DEVICE_EOF'

define Device/jdcloud_re-sp-01b
  $(Device/dsa-migration)
  IMAGE_SIZE := 27328k
  DEVICE_VENDOR := JDCloud
  DEVICE_MODEL := RE-SP-01B
  DEVICE_PACKAGES := mmc-utils kmod-fs-ext4 kmod-mt7603 kmod-mt7615e \
    kmod-mt7615-firmware kmod-sdhci-mt7620 kmod-usb3
endef
TARGET_DEVICES += jdcloud_re-sp-01b
DEVICE_EOF
fi

# ============================================================
# 添加 DTS（设备树）文件（从 OpenWrt 下载）
# ============================================================
DTS_DIR="openwrt/target/linux/ramips/dts"
if [ ! -f "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dts" ]; then
  echo "===== 下载 jdcloud_re-sp-01b DTS 文件 ====="
  # 下载 .dts 文件
  curl -sL "https://raw.githubusercontent.com/openwrt/openwrt/main/target/linux/ramips/dts/mt7621_jdcloud_re-sp-01b.dts" -o "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dts"
  # 下载 .dtsi 文件（设备硬件定义）
  curl -sL "https://raw.githubusercontent.com/openwrt/openwrt/main/target/linux/ramips/dts/mt7621_jdcloud_re-sp-01b.dtsi" -o "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dtsi"
  echo "DTS 文件已下载"
fi

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
