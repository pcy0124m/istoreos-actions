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
# ★★★ 核心修复 1：修改 board.d/02_network
#
# 问题：iStoreOS 官方没有 jdcloud,re-sp-01b，导致掉进
#       默认分支 *)，生成 "lan1 lan2 lan3 lan4" 四个 LAN 口的
#       配置。但 RE-SP-01B 只有 lan1/lan2 两个口（DSA），
#       lan3/lan4 不存在，桥接配置全部失败。
#
# 修复：用 awk 把设备条目精确插到 *) 之前。
# ============================================================
echo "===== [FIX-1] 修改 board.d/02_network ====="

BOARD_D_FILE="target/linux/ramips/mt7621/base-files/etc/board.d/02_network"

if [ -f "$BOARD_D_FILE" ]; then
  if grep -q "jdcloud,re-sp-01b" "$BOARD_D_FILE"; then
    echo "  ℹ️ 已存在，跳过"
  else
    # 用 awk 在第一个 *) 之前插入设备条目
    awk '
    !inserted && /^[[:space:]]*\*\)/ {
      print "\tjdcloud,re-sp-01b)"
      print "\t\tucidef_set_interfaces_lan_wan \"lan1 lan2\" \"wan\""
      print "\t\t;;"
      inserted=1
    }
    { print }
    ' "$BOARD_D_FILE" > "${BOARD_D_FILE}.patched" && mv "${BOARD_D_FILE}.patched" "$BOARD_D_FILE"
    chmod +x "$BOARD_D_FILE" 2>/dev/null
    echo "  ✅ board.d/02_network 已插入 jdcloud,re-sp-01b"
    # 验证
    grep -A2 "jdcloud,re-sp-01b" "$BOARD_D_FILE"
  fi
else
  # 尝试其他可能路径
  ALT_BOARD_D="target/linux/ramips/base-files/etc/board.d/02_network"
  if [ -f "$ALT_BOARD_D" ]; then
    awk '
    !inserted && /^[[:space:]]*\*\)/ {
      print "\tjdcloud,re-sp-01b)"
      print "\t\tucidef_set_interfaces_lan_wan \"lan1 lan2\" \"wan\""
      print "\t\t;;"
      inserted=1
    }
    { print }
    ' "$ALT_BOARD_D" > "${ALT_BOARD_D}.patched" && mv "${ALT_BOARD_D}.patched" "$ALT_BOARD_D"
    echo "  ✅ board.d (alt path) 已插入"
  else
    echo "  ⚠️ 未找到 board.d 文件！"
    echo "  尝试路径: $BOARD_D_FILE"
    ls -la target/linux/ramips/ 2>/dev/null || echo "  ramips 目录不存在"
  fi
fi

# ============================================================
# ★★★ 核心修复 2：创建 uci-defaults 网络配置（双保险）
#
# 在首次启动时运行，删除 config_generate 生成的错误配置，
# 写入正确的 DSA 桥接。
# ============================================================
echo "===== [FIX-2] 创建 uci-defaults 网络脚本 ====="

mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-network-fix-re-sp-01b << 'EOF_NET'
#!/bin/sh
# RE-SP-01B DSA 网络修正（首次启动执行一次）
# 固件本身就是为此设备编译的，无需检查 board_name

echo "[99-network] Fixing DSA network for JDCloud RE-SP-01B..."

# 记录当前网络状态用于调试
echo "--- BEFORE fix ---" > /root/net-debug.log 2>&1
ip link show >> /root/net-debug.log 2>&1
cat /etc/config/network >> /root/net-debug.log 2>&1

# 清除所有可能错误的默认配置
uci -q delete network.br_lan
uci -q delete network.lan
uci -q delete network.wan
uci -q delete network.wan6

# 创建 DSA 桥接设备：br-lan = lan1 + lan2
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

# WAN 接口（DTS: gmac1 label=wan）
uci set network.wan=interface
uci set network.wan.device='wan'
uci set network.wan.proto='dhcp'

# WAN6 IPv6
uci set network.wan6=interface
uci set network.wan6.device='wan'
uci set network.wan6.proto='dhcpv6'

uci commit network

# 记录修正后状态
echo "--- AFTER fix ---" >> /root/net-debug.log 2>&1
cat /etc/config/network >> /root/net-debug.log 2>&1

# 重启网络使配置生效
/etc/init.d/network restart

echo "[99-network] Done. LAN=br-lan(lan1+lan2)@DEFAULT_LAN_IP, WAN=dhcp"
EOF_NET

chmod +x files/etc/uci-defaults/99-network-fix-re-sp-01b

# 替换 IP 占位符
sed -i "s/DEFAULT_LAN_IP/${DEFAULT_IP}/g" files/etc/uci-defaults/99-network-fix-re-sp-01b
echo "  ✅ uci-defaults 已创建 (LAN IP: ${DEFAULT_IP})"

# ============================================================
# 自定义系统名称
# ============================================================
if [ -n "${OS_NAME}" ]; then
  sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='${OS_NAME}'/" package/base-files/files/etc/openwrt_release 2>/dev/null
  echo "✅ 系统名称: ${OS_NAME}"
fi

echo "✅ DIY Part2 全部完成！"
echo "  FIX-1: board.d/02_network 设备条目"
echo "  FIX-2: uci-defaults DSA 桥接覆写"
