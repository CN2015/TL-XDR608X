#!/bin/bash
#
# ============================================================================
# OpenWrt 自定义编译脚本（简化稳定版 - v3.0）
# 文件：diy-all.sh
# 描述：添加第三方源 + 预设配置 + 插件替换 + 系统定制 + WiFi 优化
# 适配：Lean 源码 (coolsnowwolf/lede) + TL-XDR6088 + Kernel 6.12
# 许可：MIT License
# 版本：v3.0 (移除手动克隆，完全依赖 feeds，避免网络失败)
# ============================================================================

set -e

# ============================================================================
# 📋 全局配置变量
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-.}"
DIY_DIR="${GITHUB_WORKSPACE:-$SCRIPT_DIR}/diy"
WGET_RETRY="wget -qO- --timeout=30 --tries=3"

echo "================================================================"
echo "🚀 OpenWrt DIY 脚本启动 (v3.0 - 简化稳定版)"
echo "📁 源码目录：$OPENWRT_DIR"
echo "📁 自定义目录：$DIY_DIR"
echo "================================================================"


# ============================================================================
# 🔧 辅助函数：检查并添加 Feed 源（避免重复 + 清理空格）
# ============================================================================
add_feed() {
    local feed_name="$1"
    local feed_url="$2"
    local feed_branch="$3"
    
    feed_url=$(echo "$feed_url" | sed 's/[[:space:]]*$//')
    
    if grep -q "^src-git $feed_name " feeds.conf.default 2>/dev/null; then
        echo "  ℹ️  Feed '$feed_name' 已存在，跳过"
    else
        if [ -n "$feed_branch" ]; then
            echo "src-git $feed_name $feed_url;$feed_branch" >> feeds.conf.default
        else
            echo "src-git $feed_name $feed_url" >> feeds.conf.default
        fi
        echo "  ✅ 已添加：$feed_name"
    fi
}


# ============================================================================
# 📡 【Part 1】添加第三方 Feed 源
# ============================================================================
echo ""
echo "📦 [Part 1] 添加第三方 Feed 源..."

add_feed "turboacc" "https://github.com/chenmozhijin/turboacc.git" "luci"
add_feed "turboaccpackage" "https://github.com/chenmozhijin/turboacc.git" "package"
add_feed "small" "https://github.com/kenzok8/small.git" ""
add_feed "kenzo" "https://github.com/kenzok8/openwrt-packages.git" ""
add_feed "nas" "https://github.com/linkease/nas-packages.git" "master"
add_feed "nas_luci" "https://github.com/linkease/nas-packages-luci.git" "main"

echo "✅ Feed 源添加完成"


# ============================================================================
# 📁 【Part 1】下载预设配置文件
# ============================================================================
echo ""
echo "📥 下载预设配置文件..."

mkdir -p files/etc/config files/etc files/etc/opkg files/root

$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/main/etc/config/openclash > files/etc/config/openclash 2>/dev/null && echo "  ✓ openclash" || echo "  ✗ openclash"
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/main/etc/config/mosdns > files/etc/config/mosdns 2>/dev/null && echo "  ✓ mosdns" || echo "  ✗ mosdns"
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/main/etc/config/smartdns > files/etc/config/smartdns 2>/dev/null && echo "  ✓ smartdns" || echo "  ✗ smartdns"
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/main/etc/opkg.conf > files/etc/opkg.conf 2>/dev/null && echo "  ✓ opkg.conf" || echo "  ✗ opkg.conf"
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/main/etc/opkg/distfeeds.conf > files/etc/opkg/distfeeds.conf 2>/dev/null && echo "  ✓ distfeeds.conf" || echo "  ✗ distfeeds.conf"
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/main/root/.profile > files/root/.profile 2>/dev/null && echo "  ✓ .profile" || echo "  ✗ .profile"

echo "✅ 预设配置文件下载完成"


# ============================================================================
# 🔄 【Part 1】更新并安装 Feed
# ============================================================================
echo ""
echo "🔄 执行 feeds update & install..."

./scripts/feeds update -a
./scripts/feeds install -a

echo "✅ Feed 更新安装完成"


# ============================================================================
# 📡 【Part 2】注入自定义 WiFi SSID 配置
# ============================================================================
echo ""
echo "📡 应用自定义 WiFi SSID 配置 (TP-LINK_前缀)..."

mkdir -p package/kernel/mac80211/files/lib/wifi/

DIY_MAC_PATH="$DIY_DIR/mac80211.sh"
if [ -f "$DIY_MAC_PATH" ]; then
    cp -f "$DIY_MAC_PATH" package/kernel/mac80211/files/lib/wifi/mac80211.sh
    chmod +x package/kernel/mac80211/files/lib/wifi/mac80211.sh
    echo "✅ mac80211.sh 已覆盖"
else
    echo "⚠️ 警告：$DIY_MAC_PATH 未找到，使用默认 WiFi 配置"
fi

mkdir -p files/etc/uci-defaults/
cat > files/etc/uci-defaults/99-wifi-ssid << 'EOF'
#!/bin/sh
[ -f "/etc/.wifi_customized" ] && exit 0

for radio in $(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1); do
    band=$(uci get wireless.$radio.band 2>/dev/null)
    mac=$(uci get wireless.$radio.macaddr 2>/dev/null)
    [ -z "$mac" ] && continue
    
    mac_suffix=$(echo "$mac" | awk -F: '{print toupper($(NF-1)$(NF))}')
    
    band_suffix=""
    [ "$band" = "5g" ] && band_suffix="_5G"
    [ "$band" = "2g" ] && band_suffix="_2G"
    
    uci set wireless.default_${radio}.ssid="TP-LINK_${mac_suffix}${band_suffix}" 2>/dev/null
    uci set wireless.default_${radio}.encryption="psk2" 2>/dev/null
    uci set wireless.default_${radio}.key="1234567890" 2>/dev/null
    uci set wireless.default_${radio}.disabled="0" 2>/dev/null
done

uci commit wireless 2>/dev/null
wifi reload 2>/dev/null

touch /etc/.wifi_customized
rm -f "$0"
exit 0
EOF
chmod +x files/etc/uci-defaults/99-wifi-ssid
echo "✅ uci-defaults 脚本已添加：99-wifi-ssid"
echo "🎯 WiFi 名称：TP-LINK_XXXX_5G / TP-LINK_XXXX_2G"


# ============================================================================
# 🗑️ 【Part 2】替换核心组件（带存在性检查）
# ============================================================================
echo ""
echo "🧹 清理并替换网络组件..."

rm -rf feeds/small/{shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn} 2>/dev/null || true
rm -rf feeds/luci/applications/{shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn} 2>/dev/null || true

for pkg in xray-core mosdns v2ray-geodata v2ray-geoip sing-box chinadns-ng dns2socks dns2tcp microsocks; do
    rm -rf feeds/packages/net/$pkg 2>/dev/null || true
    if [ -d "feeds/small/$pkg" ]; then
        cp -r feeds/small/$pkg feeds/packages/net/ && echo "  ✓ $pkg"
    else
        echo "  ℹ️  $pkg 在 small 源中不存在，使用默认版本"
    fi
done

rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-openclash 2>/dev/null || true
[ -d "feeds/small/luci-app-passwall" ] && cp -r feeds/small/luci-app-passwall feeds/luci/applications/ && echo "  ✓ luci-app-passwall" || echo "  ℹ️  passwall 未找到"
[ -d "feeds/small/luci-app-openclash" ] && cp -r feeds/small/luci-app-openclash feeds/luci/applications/ && echo "  ✓ luci-app-openclash" || echo "  ℹ️  openclash 未找到"

echo "✅ 核心组件替换完成"


# ============================================================================
# 🎨 【Part 2】Argon 主题（使用 feeds 已有版本 - 不克隆）
# ============================================================================
echo ""
echo "🎨 配置 Argon 主题（使用 feeds 已有版本）..."

rm -rf package/lean/luci-theme-argon 2>/dev/null || true
rm -rf package/lean/luci-app-argon-config 2>/dev/null || true

if [ -d "feeds/luci/themes/luci-theme-argon" ]; then
    echo "✅ feeds/luci/themes/luci-theme-argon 已存在"
else
    echo "ℹ️  未找到 luci-theme-argon，将使用默认主题"
fi

if [ -d "feeds/luci/applications/luci-app-argon-config" ]; then
    echo "✅ feeds/luci/applications/luci-app-argon-config 已存在"
else
    echo "ℹ️  未找到 luci-app-argon-config（可选）"
fi

echo "💡 提示：make menuconfig → LuCI → Themes → <*> luci-theme-argon"
echo "✅ Argon 主题配置完成（无需克隆，避免网络失败）"


# ============================================================================
# 🌍 【Part 2】系统基础配置
# ============================================================================
echo ""
echo "⚙️ 应用系统基础配置..."

sed -i "s/timezone='.*'/timezone='CST-8'/g" ./package/base-files/files/bin/config_generate
sed -i "/timezone='.*'/a\\\t\t\set system.@system[-1].zonename='Asia/Shanghai'" ./package/base-files/files/bin/config_generate
echo "  ✓ 时区：Asia/Shanghai"

sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings 2>/dev/null || true
echo "  ✓ 默认密码已清除"

echo -e "\nmsgid \"NAS\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po 2>/dev/null || true
echo -e "msgstr \"存储\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po 2>/dev/null || true

echo -e "\nmsgid \"UPnP\"" >> feeds/luci/applications/luci-app-upnp/po/zh_Hans/upnp.po 2>/dev/null || true
echo -e "msgstr \"即插即用\"" >> feeds/luci/applications/luci-app-upnp/po/zh_Hans/upnp.po 2>/dev/null || true

TURBOACC_PO=$(find ./feeds ./package -name "turboacc.po" -path "*/zh*" 2>/dev/null | head -n1)
if [ -n "$TURBOACC_PO" ] && [ -w "$TURBOACC_PO" ]; then
    if ! grep -q "msgid \"Turbo ACC 网络加速\"" "$TURBOACC_PO" 2>/dev/null; then
        echo -e "\nmsgid \"Turbo ACC 网络加速\"" >> "$TURBOACC_PO"
        echo -e "msgstr \"网络加速\"" >> "$TURBOACC_PO"
        echo "  ✓ Turbo ACC 汉化"
    fi
fi

echo "✅ 系统基础配置完成"


# ============================================================================
# 🎨 【Part 2】插件名称汉化
# ============================================================================
echo ""
echo "🎨 应用插件名称汉化..."

declare -A NAME_MAP=(
    ["Turbo ACC 网络加速"]="网络加速"
    ["实时流量监测"]="实时流量"
    ["KMS 服务器"]="KMS 激活"
    ["终端"]="TTYD 终端"
    ["USB 打印服务器"]="打印服务"
    ["Web 管理"]="网页管理"
    ["管理权"]="改密码"
    ["MWAN3 分流助手"]="分流助手"
    ["UU 游戏加速器"]="游戏加速"
    ["ShadowSocksR Plus+"]="SSR Plus+"
    ["OpenVPN 服务器"]="OpenVPN"
    ["FileBrowser"]="文件管理"
    ["UPnP"]="即插即用"
    ["Lucky 大吉"]="全能工具"
)

for old_name in "${!NAME_MAP[@]}"; do
    new_name="${NAME_MAP[$old_name]}"
    old_name_escaped=$(printf '%s\n' "$old_name" | sed 's/[\/&|\\]/\\&/g')
    new_name_escaped=$(printf '%s\n' "$new_name" | sed 's/[\/&|\\]/\\&/g')
    
    files=$(grep -rl "\"$old_name\"" ./package ./feeds 2>/dev/null | grep -E "\.(lua|po|zh-cn)$" || true)
    if [ -n "$files" ]; then
        echo "$files" | xargs -r sed -i "s|\"$old_name_escaped\"|\"$new_name_escaped\"|g" 2>/dev/null && \
        echo "  ✅ '$old_name' → '$new_name'"
    fi
done

echo "✅ 插件名称汉化完成"


# ============================================================================
# 🏷️ 【Part 2】自定义 Banner
# ============================================================================
echo ""
echo "🏷️ 应用自定义 Banner..."

cat > package/base-files/files/etc/banner << 'EOF'
  _______                     ________        __
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|
 |_______||   __|_____|__|__||________||__|  |____|
          |__| W I R E L E S S   F R E E D O M
 -----------------------------------------------------
 %D %V, %C
 -----------------------------------------------------
 
 🎯 TL-XDR6088 定制固件 | BY: CN2014
 🔗 管理地址：192.168.1.1  |  用户：root  |  密码：空
 💡 首次使用请修改默认密码
 -----------------------------------------------------
EOF

echo "✅ 自定义 Banner 已应用"


# ============================================================================
# 🔧 【Part 2】内核版本强制修改（6.12）
# ============================================================================
echo ""
echo "🔧 强制设置内核版本：6.12..."

KERNEL_FILE="target/linux/mediatek/filogic/Makefile"
if [ -f "$KERNEL_FILE" ]; then
    sed -i "s/KERNEL_PATCHVER:=*.*/KERNEL_PATCHVER:=6.12/g" "$KERNEL_FILE"
    sed -i "s/KERNEL_PATCHVER=*.*/KERNEL_PATCHVER:=6.12/g" "$KERNEL_FILE"
    echo "  ✓ 已修改：$KERNEL_FILE"
else
    sed -i "s/KERNEL_PATCHVER:=*.*/KERNEL_PATCHVER:=6.12/g" target/linux/mediatek/Makefile 2>/dev/null || true
    echo "  ✓ 已修改：target/linux/mediatek/Makefile"
fi

sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='TL-XDR6088-$(date +%Y%m%d)'/g" package/lean/default-settings/files/zzz-default-settings 2>/dev/null || true
echo "  ✓ 固件版本标识已更新"

echo "✅ 内核配置完成"


# ============================================================================
# ✅ 执行完成
# ============================================================================
echo ""
echo "================================================================"
echo "✅ DIY 脚本执行完成！(v3.0 - 简化稳定版)"
echo "================================================================"
echo "📋 已应用配置："
echo "   • 第三方 Feed 源：turboacc / small / kenzo / nas"
echo "   • 预设配置：OpenClash / MosDNS / SmartDNS / opkg"
echo "   • WiFi 定制：TP-LINK_XXXX_5G/2G 自动命名"
echo "   • 主题：feeds 已有 luci-theme-argon（无需克隆）"
echo "   • 插件汉化：20+ 菜单名称精简"
echo "   • 系统优化：时区/密码/Banner/内核 6.12"
echo ""
echo "🚀 下一步操作："
echo "   1. make menuconfig"
echo "      → LuCI → Themes → <*> luci-theme-argon"
echo "      → LuCI → Applications → <*> luci-app-argon-config"
echo "   2. make defconfig"
echo "   3. make -j$(nproc) V=s"
echo ""
echo "💡 提示："
echo "   • 本脚本已移除所有手动 git clone，避免网络失败"
echo "   • 如遇插件冲突，请在 menuconfig 中手动调整"
echo "   • 编译失败时查看日志搜索 'ERROR' 定位问题"
echo "================================================================"

exit 0
