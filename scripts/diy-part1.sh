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
# 添加 DTS（设备树）文件
# 注意：raw.githubusercontent.com 的分支用 main（文件存在于 main）
# ============================================================
DTS_DIR="openwrt/target/linux/ramips/dts"
DTS_URL_BASE="https://raw.githubusercontent.com/openwrt/openwrt/main/target/linux/ramips/dts"

# 下载主 DTS 文件
if [ ! -f "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dts" ]; then
  echo "===== 下载 jdcloud_re-sp-01b DTS 文件 ====="
  curl -sfL "$DTS_URL_BASE/mt7621_jdcloud_re-sp-01b.dts" -o "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dts"
  if [ $? -ne 0 ] || [ ! -s "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dts" ]; then
    echo "❌ DTS 下载失败！使用内嵌版本..."
    # 如果下载失败，用内嵌的最小化 DTS
    cat > "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dts" << 'DTS_EMBED'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

#include "mt7621.dtsi"

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>
#include <dt-bindings/leds/common.h>

/ {
	compatible = "jdcloud,re-sp-01b", "mediatek,mt7621-soc";
	model = "JDCloud RE-SP-01B";

	aliases {
		led-boot = &led_status_red;
		led-failsafe = &led_status_red;
		led-running = &led_status_green;
		led-upgrade = &led_status_blue;
	};

	chosen {
		bootargs = "console=ttyS0,115200";
	};

	keys {
		compatible = "gpio-keys";

		reset {
			label = "reset";
			gpios = <&gpio 18 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_RESTART>;
		};
	};

	leds {
		compatible = "gpio-leds";

		led_status_red: led-red {
			function = LED_FUNCTION_STATUS;
			color = <LED_COLOR_ID_RED>;
			gpios = <&gpio 6 GPIO_ACTIVE_LOW>;
		};

		led_status_green: led-green {
			function = LED_FUNCTION_STATUS;
			color = <LED_COLOR_ID_GREEN>;
			gpios = <&gpio 8 GPIO_ACTIVE_LOW>;
		};

		led_status_blue: led-blue {
			function = LED_FUNCTION_STATUS;
			color = <LED_COLOR_ID_BLUE>;
			gpios = <&gpio 12 GPIO_ACTIVE_LOW>;
		};
	};
};

&sdhci {
	status = "okay";
};

&spi0 {
	status = "okay";

	flash@0 {
		compatible = "jedec,spi-nor";
		reg = <0>;
		spi-max-frequency = <50000000>;

		partitions {
			compatible = "fixed-partitions";
			#address-cells = <1>;
			#size-cells = <1>;

			partition@0 {
				label = "u-boot";
				reg = <0x0 0x30000>;
				read-only;
			};
			partition@30000 {
				label = "config";
				reg = <0x30000 0x10000>;
				read-only;
			};
			partition@40000 {
				label = "factory";
				reg = <0x40000 0x10000>;
				read-only;

				nvmem-layout {
					compatible = "fixed-layout";
					#address-cells = <1>;
					#size-cells = <1>;
					eeprom_factory_0: eeprom@0 {
						reg = <0x0 0x400>;
					};
					eeprom_factory_8000: eeprom@8000 {
						reg = <0x8000 0x4da8>;
					};
				};
			};
			partition@50000 {
				compatible = "denx,uimage";
				label = "firmware";
				reg = <0x50000 0x1ab0000>;
			};
			partition@1b00000 {
				label = "mini";
				reg = <0x1b00000 0x400000>;
				read-only;
			};
			partition@1f00000 {
				label = "oem";
				reg = <0x1f00000 0x100000>;
				read-only;
			};
		};
	};
};

&gmac1 {
	status = "okay";
	label = "wan";
	phy-handle = <&ethphy0>;
};

&ethphy0 {
	/delete-property/ interrupts;
};

&switch0 {
	ports {
		port@1 {
			status = "okay";
			label = "lan1";
		};
		port@2 {
			status = "okay";
			label = "lan2";
		};
	};
};

&pcie {
	status = "okay";
};

&pcie0 {
	wifi@0,0 {
		compatible = "mediatek,mt76";
		reg = <0x0000 0 0 0 0>;
		nvmem-cells = <&eeprom_factory_0>;
		nvmem-cell-names = "eeprom";
	};
};

&pcie1 {
	wifi@0,0 {
		compatible = "mediatek,mt76";
		reg = <0x0000 0 0 0 0>;
		nvmem-cells = <&eeprom_factory_8000>;
		nvmem-cell-names = "eeprom";
		ieee80211-freq-limit = <5000000 6000000>;
	};
};

&state_default {
	gpio {
		groups = "uart2", "uart3", "wdt";
		function = "gpio";
	};
};
DTS_EMBED
    echo "内嵌 DTS 已写入"
  fi
  echo "DTS 主文件已就绪"
fi

# 检查是否有 DTSI 文件（通常不需要，这个设备的 DTS 已经完整包含所有信息）
if [ ! -f "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dtsi" ]; then
  curl -sfL "$DTS_URL_BASE/mt7621_jdcloud_re-sp-01b.dtsi" -o "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dtsi" 2>/dev/null
  if [ $? -eq 0 ] && [ -s "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dtsi" ]; then
    echo "DTSI 文件已下载"
  else
    echo "⚠️ 无 DTSI 文件（正常，此设备无需独立 dtsi）"
    rm -f "$DTS_DIR/mt7621_jdcloud_re-sp-01b.dtsi" 2>/dev/null
  fi
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
