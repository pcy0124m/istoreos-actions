#!/bin/bash
# ============================================================
# diy-part2.sh — iStoreOS 配置自定义修改
# 在更新 feeds 后、编译之前执行
# 工作目录：openwrt/（已在 openwrt 目录下运行）
# ============================================================
BRANCH="$1"
TARGET="$2"
echo "diy-part2.sh run, branch:${BRANCH}, target:${TARGET}"

DEFAULT_IP="${LAN_IP:-192.168.12.1}"
echo "LAN_IP=${DEFAULT_IP}, OS_NAME=${OS_NAME:-iStore OS}"

# ============================================================
# ★★★ 核心修复：为 jdcloud,re-sp-01b 创建 DSA 网络配置
#
# RE-SP-01B 硬件结构：
#   - LAN 口: 通过 MT7530 DSA 交换机（port@1=lan1, port@2=lan2）
#   - WAN 口: 通过 gmac1 直连 ethphy0（DTS label=wan）
#   - CPU→Switch: port@6 通过 gmac0 RGMII 连接
#
# 问题：iStoreOS 官方无此设备定义，编译出的固件没有
#       正确的 board.d/02_network 条目，导致 /etc/config/network
#       不会自动桥接 lan1+lan2 为 br-lan，LAN 口全死。
#
# 修复：注入 uci-defaults 脚本，首次启动时强制写入正确配置。
# ============================================================
echo "===== 创建 DSA 网络 uci-defaults ====="

mkdir -p files/etc/uci-defaults

# 写入 uci-defaults 脚本（注意：外层 heredoc 用 'EOF' 防止变量展开）
cat > files/etc/uci-defaults/99-network-re-sp-01b << 'EOF_SCRIPT'
#!/bin/sh
# RE-SP-01B DSA 网络配置 — 首次启动时运行
# 只针对此设备
BOARD_NAME=$(cat /tmp/sysinfo/board_name 2>/dev/null)
[ "$BOARD_NAME" = "jdcloud,re-sp-01b" ] || exit 0

echo "[99-network] Configuring DSA network for JDCloud RE-SP-01B..."

# 删除 config_generate 可能生成的默认（不正确的）配置
uci -q delete network.br_lan
uci -q delete network.lan
uci -q delete network.wan
uci -q delete network.wan6

# 创建 DSA 桥接设备：br-lan 包含 lan1 + lan2
uci set network.br_lan=device
uci set network.br_lan.name='br-lan'
uci set network.br_lan.type='bridge'
uci add_list network.br_lan.ports='lan1'
uci add_list network.br_lan.ports='lan2'

# LAN 接口
uci set network.lan=interface
uci set network.lan.device='br-lan'
uci set network.lan.proto='static'
uci set network.lan.ipaddr='DEFAULT_LAN_IP'
uci set network.lan.netmask='255.255.255.0'

# WAN 接口（DTS 中 gmac1 label=wan）
uci set network.wan=interface
uci set network.wan.device='wan'
uci set network.wan.proto='dhcp'

# WAN6 IPv6
uci set network.wan6=interface
uci set network.wan6.device='wan'
uci set network.wan6.proto='dhcpv6'

uci commit network
echo "[99-network] Done: br-lan(lan1+lan2) ip=DEFAULT_LAN_IP, wan=dhcp"
EOF_SCRIPT

chmod +x files/etc/uci-defaults/99-network-re-sp-01b

# 用实际 IP 替换占位符
sed -i "s/DEFAULT_LAN_IP/${DEFAULT_IP}/g" files/etc/uci-defaults/99-network-re-sp-01b
echo "✅ uci-defaults 已创建 (LAN IP: ${DEFAULT_IP})"

# ============================================================
# board.d 补丁（双保险）
# 如果 iStoreOS 源码有 ramips mt7621 的 board.d 目录，
# 在 02_network 中追加设备条目
# ============================================================
echo "===== 检查 board.d 补丁 ====="

BOARD_D_FILE="target/linux/ramips/mt7621/base-files/etc/board.d/02_network"
if [ -f "$BOARD_D_FILE" ]; then
  if ! grep -q "jdcloud,re-sp-01b" "$BOARD_D_FILE"; then
    sed -i '/^\tesac$/i\\tjdcloud,re-sp-01b)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2" "wan"\n\t\t;;' "$BOARD_D_FILE"
    echo "✅ board.d/02_network 已添加设备条目"
  else
    echo "ℹ️ board.d 已有该设备配置，跳过"
  fi
else
  # iStoreOS 可能使用不同路径
  ALT_BOARD_D="target/linux/ramips/base-files/etc/board.d/02_network"
  if [ -f "$ALT_BOARD_D" ]; then
    if ! grep -q "jdcloud,re-sp-01b" "$ALT_BOARD_D"; then
      sed -i '/^\tesac$/i\\tjdcloud,re-sp-01b)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2" "wan"\n\t\t;;' "$ALT_BOARD_D"
      echo "✅ board.d (alt path) 已添加设备条目"
    fi
  else
    echo "⚠️ 未找到 board.d 文件，跳过（uci-defaults 仍然生效）"
  fi
fi

# ============================================================
# 自定义系统名称
# ============================================================
if [ -n "${OS_NAME}" ]; then
  sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='${OS_NAME}'/" package/base-files/files/etc/openwrt_release 2>/dev/null
  echo "✅ 系统名称: ${OS_NAME}"
fi

# ============================================================
# WiFi
# ============================================================
if [ "$ENABLE_WIFI" = "true" ]; then
  echo "✅ WiFi 已启用"
else
  echo "⏭️ WiFi 未启用"
fi

echo "✅ DIY Part2 完成！"
