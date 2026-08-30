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
# ============================================================
echo "===== [FIX-1] 修改 board.d/02_network ====="

BOARD_D_FILE="target/linux/ramips/mt7621/base-files/etc/board.d/02_network"

if [ -f "$BOARD_D_FILE" ]; then
  if grep -q "jdcloud,re-sp-01b" "$BOARD_D_FILE"; then
    echo "  ℹ️ 已存在，跳过"
  else
    awk '
    !inserted && /^[[:space:]]*\*\)/ {
      print "\tjdcloud,re-sp-01b)"
      print "\t\tucidef_set_interfaces_lan_wan \"lan1 lan2\" \"wan\""
      print "\t\t;;"
      inserted=1
    }
    { print }
    ' "$BOARD_D_FILE" > "${BOARD_D_FILE}.patched" && mv "${BOARD_D_FILE}.patched" "$BOARD_D_FILE"
    echo "  ✅ board.d/02_network 已插入 jdcloud,re-sp-01b"
    grep -n "jdcloud,re-sp-01b" "$BOARD_D_FILE"
  fi
else
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
  fi
fi

# ============================================================
# ★★★ 核心修复 2：uci-defaults 网络 + WiFi + 诊断日志
# ============================================================
echo "===== [FIX-2] 创建 uci-defaults 脚本 ====="

mkdir -p files/etc/uci-defaults

# --- 网络修复脚本 ---（用 'EOF' 防止构建时展开任何变量）---
cat > files/etc/uci-defaults/99-network-fix-re-sp-01b << 'EOF_NET'
#!/bin/sh
echo "[99-network] Fixing DSA network..." >> /root/diag.log

# 记录系统信息用于远程诊断
echo "=== DIAG INFO $(date) ===" > /root/diag.log
echo "--- uname ---" >> /root/diag.log
uname -a >> /root/diag.log 2>&1
echo "--- ALL interfaces ---" >> /root/diag.log
ip link show >> /root/diag.log 2>&1
echo "--- /sys/class/net ---" >> /root/diag.log
ls /sys/class/net/ >> /root/diag.log 2>&1
echo "--- dmesg mt753/mt7530/dsa/switch ---" >> /root/diag.log
dmesg | grep -i -E "mt753|dsa|switch|lan[0-9]|eth[0-9]" >> /root/diag.log 2>&1
echo "--- loaded modules ---" >> /root/diag.log
lsmod >> /root/diag.log 2>&1
echo "--- /etc/config/network BEFORE fix ---" >> /root/diag.log
cat /etc/config/network >> /root/diag.log 2>&1

# 清除可能错误的默认网络配置
uci -q delete network.br_lan
uci -q delete network.lan
uci -q delete network.wan
uci -q delete network.wan6

# DSA 桥接：br-lan = lan1 + lan2
uci set network.br_lan=device
uci set network.br_lan.name='br-lan'
uci set network.br_lan.type='bridge'
uci add_list network.br_lan.ports='lan1'
uci add_list network.br_lan.ports='lan2'

# LAN
uci set network.lan=interface
uci set network.lan.device='br-lan'
uci set network.lan.proto='static'
uci set network.lan.ipaddr='IP_PLACEHOLDER'
uci set network.lan.netmask='255.255.255.0'

# WAN
uci set network.wan=interface
uci set network.wan.device='wan'
uci set network.wan.proto='dhcp'

# WAN6
uci set network.wan6=interface
uci set network.wan6.device='wan'
uci set network.wan6.proto='dhcpv6'

uci commit network

echo "--- /etc/config/network AFTER fix ---" >> /root/diag.log
uci show network >> /root/diag.log 2>&1

# 记录网络接口是否存在
echo "--- check lan1 lan2 wan exist ---" >> /root/diag.log
ls /sys/class/net/lan1 2>&1 >> /root/diag.log
ls /sys/class/net/lan2 2>&1 >> /root/diag.log
ls /sys/class/net/wan 2>&1 >> /root/diag.log

/etc/init.d/network restart
echo "[99-network] Done." >> /root/diag.log
EOF_NET

# 替换 IP 占位符
sed -i "s/IP_PLACEHOLDER/${DEFAULT_IP}/g" files/etc/uci-defaults/99-network-fix-re-sp-01b
echo "  ✅ 网络修复脚本已创建 (LAN IP: ${DEFAULT_IP})"

# --- WiFi 诊断开启脚本 ---
cat > files/etc/uci-defaults/98-wifi-diag << 'EOF_WIFI'
#!/bin/sh
# 诊断模式：开启 WiFi 用于远程访问
# SSID: JDCloud-Diag / 密码: jdcloud2026

echo "[98-wifi] Enabling WiFi..." >> /root/diag.log

# 删除系统自动生成的默认无线配置，避免干扰
uci -q delete wireless.radio0
uci -q delete wireless.radio1
uci -q delete wireless.default_radio0
uci -q delete wireless.default_radio1
uci -q delete wireless.wwan0
uci -q delete wireless.sta0

# 先让系统重新生成无线设备配置
/etc/init.d/system reload 2>/dev/null
wifi detect > /tmp/wifi_detect.txt 2>/dev/null || true

# 尝试用 wifi detect 的输出重新生成配置
# 如果不行，直接手动设置

# radio0 配置（通常是 2.4GHz）
uci set wireless.radio0=wifi-device
uci set wireless.radio0.type='mac80211'
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='CN'
uci set wireless.radio0.band='2g'
uci set wireless.radio0.channel='6'

uci set wireless.default_radio0=wifi-iface
uci set wireless.default_radio0.device='radio0'
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.network='lan'
uci set wireless.default_radio0.ssid='JDCloud-Diag'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key='jdcloud2026'

# radio1 配置（通常是 5GHz）
uci set wireless.radio1=wifi-device
uci set wireless.radio1.type='mac80211'
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.country='CN'
uci set wireless.radio1.band='5g'
uci set wireless.radio1.channel='36'

uci set wireless.default_radio1=wifi-iface
uci set wireless.default_radio1.device='radio1'
uci set wireless.default_radio1.mode='ap'
uci set wireless.default_radio1.network='lan'
uci set wireless.default_radio1.ssid='JDCloud-Diag-5G'
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.default_radio1.key='jdcloud2026'

uci commit wireless

echo "[98-wifi] Config done, trying to start..." >> /root/diag.log
# 启动无线
/etc/init.d/network restart 2>/dev/null
/sbin/wifi down 2>/dev/null
/sbin/wifi up 2>/dev/null

echo "[98-wifi] WiFi enabled. SSID: JDCloud-Diag / jdcloud2026" >> /root/diag.log
EOF_WIFI

chmod +x files/etc/uci-defaults/98-wifi-diag

echo "  ✅ uci-defaults 网络+WiFi 脚本已创建"

# ============================================================
# ★★★ 确保 WiFi 相关包编入 .config
# ============================================================
echo "===== [FIX-3] 确保 WiFi 包 ====="

cat >> .config << 'EOF_CFG'

# WiFi 必须组件（wpad-basic 提供 WPA2-PSK）
CONFIG_PACKAGE_wpad-basic-mbedtls=y
CONFIG_PACKAGE_wpa-cli=y
CONFIG_PACKAGE_iwinfo=y
CONFIG_PACKAGE_kmod-cfg80211=y
CONFIG_PACKAGE_kmod-mt7603=y
CONFIG_PACKAGE_kmod-mt7615e=y
CONFIG_PACKAGE_kmod-mt7615-firmware=y
EOF_CFG

echo "  ✅ WiFi 包已追加到 .config"

# ============================================================
# 自定义系统名称
# ============================================================
if [ -n "${OS_NAME}" ]; then
  sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='${OS_NAME}'/" package/base-files/files/etc/openwrt_release 2>/dev/null
  echo "✅ 系统名称: ${OS_NAME}"
fi

echo "✅ DIY Part2 全部完成！"
echo "  FIX-1: board.d/02_network 设备条目"
echo "  FIX-2: uci-defaults 网络+WiFi+诊断日志"
echo "  FIX-3: WiFi 相关包"
echo "  WiFi 诊断: SSID=JDCloud-Diag Key=jdcloud2026"
