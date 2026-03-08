#!/bin/bash
#
# ============================================================================
# OpenWrt 自定义编译脚本（完整合并版 - 最终修复）
# 文件: diy-all.sh
# 描述: 添加第三方源 + 预设配置 + 插件替换 + 系统定制 + WiFi/主题优化
# 适配: Lean 源码 (coolsnowwolf/lede) + TL-XDR6088
# 作者: 基于 P3TERX/Actions-OpenWrt 修改
# 许可: MIT License
# 版本: v2.1 (修复 Duplicate feed / 汉化路径 / 网络超时)
# ============================================================================

set -e  # 遇错立即退出，避免错误累积

# ============================================================================
# 📋 全局配置变量
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-.}"
DIY_DIR="${GITHUB_WORKSPACE:-$SCRIPT_DIR}/diy"
WGET_RETRY="wget -qO- --timeout=30 --tries=3"

echo "================================================================"
echo "🚀 OpenWrt DIY 脚本启动 (v2.1)"
echo "📁 源码目录: $OPENWRT_DIR"
echo "📁 自定义目录: $DIY_DIR"
echo "================================================================"


# ============================================================================
# 📡 【Part 1】添加第三方 Feed 源（带重复检测）
# 执行时机：在 ./scripts/feeds update -a 之前
# ============================================================================
echo ""
echo "📦 [Part 1] 添加第三方 Feed 源..."

# 🔧 辅助函数：检查并添加 Feed 源（避免重复）
add_feed() {
    local feed_name="$1"
    local feed_url="$2"
    local feed_branch="$3"
    
    # 检查是否已存在该 feed 名称
    if grep -q "^src-git $feed_name " feeds.conf.default 2>/dev/null; then
        echo "  ℹ️  Feed '$feed_name' 已存在，跳过添加"
    else
        if [ -n "$feed_branch" ]; then
            echo "src-git $feed_name $feed_url;$feed_branch" >> feeds.conf.default
        else
            echo "src-git $feed_name $feed_url" >> feeds.conf.default
        fi
        echo "  ✅ 已添加 Feed: $feed_name"
    fi
}

# 🔧 Turbo ACC 网络加速（luci + package 分离）
add_feed "turboacc" "https://github.com/chenmozhijin/turboacc.git" "luci"
add_feed "turboaccpackage" "https://github.com/chenmozhijin/turboacc.git" "package"

# 🔌 VLMCSd KMS 激活服务
add_feed "appvlmcsd" "https://github.com/AutoCONFIG/luci-app-vlmcsd" "master"

# 🎨 Argon 主题（备用，实际使用下方 git clone 方式）
add_feed "theme" "https://github.com/sbwml/luci-theme-argon" ""

# 📦 kenzok8 插件集合（small + openwrt-packages）
add_feed "small" "https://github.com/kenzok8/small" ""
add_feed "kenzo" "https://github.com/kenzok8/openwrt-packages" ""

echo "✅ Feed 源添加完成"


# ============================================================================
# 📁 【Part 1】下载预设配置文件（来自 TL-XDR608X 项目）
# ============================================================================
echo ""
echo "📥 下载预设配置文件..."

mkdir -p files/etc/config files/etc files/etc/opkg files/root

# OpenClash / MosDNS / SmartDNS 配置（带超时重试）
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/openclash > files/etc/config/openclash 2>/dev/null && echo "  ✓ openclash" || echo "  ✗ openclash 下载失败"
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/mosdns > files/etc/config/mosdns 2>/dev/null && echo "  ✓ mosdns" || echo "  ✗ mosdns 下载失败"
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/smartdns > files/etc/config/smartdns 2>/dev/null && echo "  ✓ smartdns" || echo "  ✗ smartdns 下载失败"

# opkg 包管理器配置
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/opkg.conf > files/etc/opkg.conf 2>/dev/null && echo "  ✓ opkg.conf" || echo "  ✗ opkg.conf 下载失败"
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/distfeeds.conf > files/etc/opkg/distfeeds.conf 2>/dev/null && echo "  ✓ distfeeds.conf" || echo "  ✗ distfeeds.conf 下载失败"

# 用户环境变量
$WGET_RETRY https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/.profile > files/root/.profile 2>/dev/null && echo "  ✓ .profile" || echo "  ✗ .profile 下载失败"

echo "✅ 预设配置文件下载完成"


# ============================================================================
# 🔄 【Part 1】更新并安装 Feed（关键步骤！）
# ============================================================================
echo ""
echo "🔄 执行 feeds update & install..."

./scripts/feeds update -a
./scripts/feeds install -a

echo "✅ Feed 更新安装完成"


# ============================================================================
# 📡 【Part 2】注入自定义 mac80211.sh (WiFi SSID: TP-LINK_XXXX)
# ============================================================================
echo ""
echo "📡 应用自定义 WiFi SSID 配置 (TP-LINK_前缀)..."

# 1. 确保目标目录存在
mkdir -p package/kernel/mac80211/files/lib/wifi/

# 2. 复制 diy/mac80211.sh 覆盖源码（支持本地/Actions 双模式）
DIY_MAC_PATH="$DIY_DIR/mac80211.sh"
if [ -f "$DIY_MAC_PATH" ]; then
    cp -f "$DIY_MAC_PATH" package/kernel/mac80211/files/lib/wifi/mac80211.sh
    chmod +x package/kernel/mac80211/files/lib/wifi/mac80211.sh
    echo "✅ mac80211.sh 已覆盖: package/kernel/mac80211/files/lib/wifi/"
else
    echo "⚠️ 警告: $DIY_MAC_PATH 未找到，将使用默认 WiFi 配置"
fi

# 3. 添加 uci-defaults 首启脚本（双重保障：首次启动自动配置 WiFi）
mkdir -p files/etc/uci-defaults/
cat > files/etc/uci-defaults/99-wifi-ssid <<- 'EOF'
#!/bin/sh
# 首次启动时应用自定义 WiFi SSID（避免重复执行）
[ -f "/etc/.wifi_customized" ] && exit 0

# 遍历所有 radio 配置
for radio in $(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1); do
    band=$(uci get wireless.$radio.band 2>/dev/null)
    mac=$(uci get wireless.$radio.macaddr 2>/dev/null)
    [ -z "$mac" ] && continue
    
    # 提取 MAC 最后 4 位（大写）
    mac_suffix=$(echo "$mac" | awk -F: '{print toupper($(NF-1)$(NF))}')
    
    # 频段后缀
    band_suffix=""
    [ "$band" = "5g" ] && band_suffix="_5G"
    [ "$band" = "2g" ] && band_suffix="_2G"
    
    # 应用配置
    uci set wireless.default_${radio}.ssid="TP-LINK_${mac_suffix}${band_suffix}" 2>/dev/null
    uci set wireless.default_${radio}.encryption="psk2" 2>/dev/null
    uci set wireless.default_${radio}.key="1234567890" 2>/dev/null
    uci set wireless.default_${radio}.disabled="0" 2>/dev/null
done

uci commit wireless 2>/dev/null
wifi reload 2>/dev/null

# 标记已配置 + 删除自身
touch /etc/.wifi_customized
rm -f "$0"
exit 0
EOF
chmod +x files/etc/uci-defaults/99-wifi-ssid
echo "✅ uci-defaults 脚本已添加: 99-wifi-ssid"
echo "🎯 WiFi 名称格式: TP-LINK_XXXX_5G / TP-LINK_XXXX_2G"


# ============================================================================
# 🗑️ 【Part 2】移除冲突插件 & 替换核心组件
# ============================================================================
echo ""
echo "🧹 清理并替换网络组件..."

# 移除旧版/冲突的科学上网插件
rm -rf feeds/small/{shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-wol,luci-app-bypass} 2>/dev/null || true
rm -rf feeds/luci/applications/{shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-wol,luci-app-bypass} 2>/dev/null || true
rm -rf feeds/luci/packages/net/{shadowsocksr-libev-ssr-check,shadowsocksr-libev-ssr-local,shadowsocksr-libev-ssr-redir,shadowsocksr-libev-ssr-server} 2>/dev/null || true

# 替换 packages 源中的核心组件为 small 源版本（确保新版兼容）
for pkg in xray-core mosdns v2ray-geodata v2ray-geoip sing-box chinadns-ng dns2socks dns2tcp microsocks; do
    rm -rf feeds/packages/net/$pkg 2>/dev/null || true
    cp -r feeds/small/$pkg feeds/packages/net/ 2>/dev/null && echo "  ✓ $pkg" || echo "  ✗ $pkg 替换失败"
done

# 更新 FQ 插件（PassWall + OpenClash）
rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-openclash 2>/dev/null || true
cp -r feeds/small/luci-app-passwall feeds/luci/applications/ 2>/dev/null && echo "  ✓ luci-app-passwall" || echo "  ✗ luci-app-passwall 替换失败"
cp -r feeds/small/luci-app-openclash feeds/luci/applications/ 2>/dev/null && echo "  ✓ luci-app-openclash" || echo "  ✗ luci-app-openclash 替换失败"

echo "✅ 核心组件替换完成"


# ============================================================================
# 🎨 【Part 2】替换 Argon 主题为 jerrykuku 官方 18.06 版本
# ============================================================================
echo ""
echo "🎨 应用 jerrykuku/luci-theme-argon (18.06 分支)..."

# 🔹 清理旧版本（避免冲突）
rm -rf feeds/luci/themes/luci-theme-argon 2>/dev/null || true
rm -rf package/lean/luci-theme-argon 2>/dev/null || true
rm -rf package/lean/luci-app-argon-config 2>/dev/null || true

# 🔹 克隆官方主题（18.06 分支适配 Lean 源码）
THEME_TARGET_DIR="package/lean/luci-theme-argon"
[ ! -d "package/lean" ] && THEME_TARGET_DIR="package/themes/luci-theme-argon" && mkdir -p package/themes

if git clone -b 18.06 --depth=1 --timeout=30 https://github.com/jerrykuku/luci-theme-argon.git "$THEME_TARGET_DIR" 2>/dev/null; then
    echo "✅ 已克隆: luci-theme-argon (18.06) → $THEME_TARGET_DIR"
else
    echo "❌ 克隆 luci-theme-argon 失败，请检查网络连接"
fi

# 🔹 （推荐）克隆配套配置插件
CONFIG_TARGET_DIR="package/lean/luci-app-argon-config"
[ ! -d "package/lean" ] && CONFIG_TARGET_DIR="package/luci-app-argon-config"

if git clone --depth=1 --timeout=30 https://github.com/jerrykuku/luci-app-argon-config.git "$CONFIG_TARGET_DIR" 2>/dev/null; then
    echo "✅ 已克隆: luci-app-argon-config → $CONFIG_TARGET_DIR"
else
    echo "ℹ️  未克隆配置插件，可手动在 menuconfig 中启用"
fi

echo "💡 提示: 执行 'make menuconfig' → LuCI → Themes → 勾选 <*> luci-theme-argon"


# ============================================================================
# 🌍 【Part 2】系统基础配置（时区 / 密码 / 汉化）- 安全版
# ============================================================================
echo ""
echo "⚙️ 应用系统基础配置..."

# 修改默认时区为中国上海
sed -i "s/timezone='.*'/timezone='CST-8'/g" ./package/base-files/files/bin/config_generate
sed -i "/timezone='.*'/a\\\t\t\set system.@system[-1].zonename='Asia/Shanghai'" ./package/base-files/files/bin/config_generate
echo "  ✓ 时区设置为 Asia/Shanghai"

# 清除默认登录密码（首次登录需自行设置）
sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings 2>/dev/null || true
echo "  ✓ 默认密码已清除"

# 补充中文汉化条目（基础模块）- 添加 2>/dev/null 避免文件不存在时报错
echo -e "\nmsgid \"NAS\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po 2>/dev/null || true
echo -e "msgstr \"存储\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po 2>/dev/null || true

echo -e "\nmsgid \"UPnP\"" >> feeds/luci/applications/luci-app-upnp/po/zh_Hans/upnp.po 2>/dev/null || true
echo -e "msgstr \"即插即用\"" >> feeds/luci/applications/luci-app-upnp/po/zh_Hans/upnp.po 2>/dev/null || true

# 🔧 Turbo ACC 汉化（使用 find 动态查找路径）
TURBOACC_PO=$(find ./feeds ./package -name "turboacc.po" -path "*/zh*" 2>/dev/null | head -n1)
if [ -n "$TURBOACC_PO" ] && [ -w "$TURBOACC_PO" ]; then
    if ! grep -q "msgid \"Turbo ACC 网络加速\"" "$TURBOACC_PO" 2>/dev/null; then
        echo -e "\nmsgid \"Turbo ACC 网络加速\"" >> "$TURBOACC_PO"
        echo -e "msgstr \"网络加速\"" >> "$TURBOACC_PO"
        echo "  ✓ Turbo ACC 汉化: $TURBOACC_PO"
    fi
fi

# 🔧 Argon Config 汉化（多路径兼容 + 防重复 + 安全写入）
ARGON_PO=$(find ./package ./feeds -name "argon-config.po" -path "*/zh*" 2>/dev/null | head -n1)
if [ -n "$ARGON_PO" ] && [ -w "$ARGON_PO" ]; then
    if ! grep -q "msgid \"Argon 主题设置\"" "$ARGON_PO" 2>/dev/null; then
        echo -e "\nmsgid \"Argon 主题设置\"" >> "$ARGON_PO"
        echo -e "msgstr \"主题设置\"" >> "$ARGON_PO"
        echo "  ✓ Argon Config 汉化: $ARGON_PO"
    else
        echo "  ℹ️  Argon Config 汉化已存在，跳过"
    fi
else
    echo "  ℹ️  未找到 argon-config.po 汉化文件，跳过（不影响使用）"
fi

echo "✅ 系统基础配置完成"


# ============================================================================
# 🎨 【Part 2】批量修改 LuCI 插件显示名称（精简中文）
# ============================================================================
echo ""
echo "🎨 应用插件名称汉化/精简..."

# 定义替换规则（关联数组：原名称 → 精简名称）
declare -A NAME_MAP=(
    ["aMule设置"]="电驴下载"
    ["Turbo ACC 网络加速"]="网络加速"
    ["实时流量监测"]="实时流量"
    ["KMS 服务器"]="KMS激活"
    ["终端"]="TTYD终端"
    ["USB 打印服务器"]="打印服务"
    ["Web 管理"]="网页管理"
    ["管理权"]="改密码"
    ["带宽监控"]="带宽监视"
    ["设置向导"]="向导"
    ["挂载 SMB 网络共享"]="SMB网络共享"
    ["解锁网易云灰色歌曲"]="解锁网易云"
    ["AirPlay 2 音频接收器"]="音频接收器"
    ["MWAN3 分流助手"]="分流助手"
    ["UU游戏加速器"]="游戏加速"
    ["ShadowSocksR Plus+"]="SSR Plus+"
    ["广告屏蔽大师 Plus+"]="屏广大师"
    ["iKoolProxy 滤广告"]="过滤广告"
    ["DDNSTO 远程控制"]="远程控制"
    ["Argon 主题设置"]="主题设置"
    ["AdGuard Home"]="AdGuard"
    ["Alist 文件列表"]="网盘搜刮"
    ["Alist"]="网盘搜刮"
    ["SoftEther VPN 服务器"]="SoftEther"
    ["OpenVPN 服务器"]="OpenVPN"
    ["IPSec VPN 服务器"]="IPSec VPN"
    ["PPTP VPN 服务器"]="PPTP VPN"
    ["FileBrowser"]="文件管理"
    ["Online User"]="在线用户"
    ["备份与升级"]="备份/升级"
    ["UPnP"]="即插即用"
    ["监控"]="带宽监视"
    ["Lucky大吉"]="全能工具"
    ["udpxy"]="电视组播"
)

# 遍历执行替换（使用 | 作为 sed 分隔符，避免 / 冲突）
for old_name in "${!NAME_MAP[@]}"; do
    new_name="${NAME_MAP[$old_name]}"
    
    # 转义特殊字符：/ & | \ （避免 sed 解析错误）
    old_name_escaped=$(printf '%s\n' "$old_name" | sed 's/[\/&|\\]/\\&/g')
    new_name_escaped=$(printf '%s\n' "$new_name" | sed 's/[\/&|\\]/\\&/g')
    
    # 查找包含旧名称的文件（限制文件类型，提升效率）
    files=$(grep -rl "\"$old_name\"" ./package ./feeds 2>/dev/null | grep -E "\.(lua|po|zh-cn)$" || true)
    if [ -n "$files" ]; then
        echo "$files" | xargs -r sed -i "s|\"$old_name_escaped\"|\"$new_name_escaped\"|g" 2>/dev/null && \
        echo "  ✅ '$old_name' → '$new_name'"
    fi
done

echo "✅ 插件名称汉化完成"


# ============================================================================
# 🏷️ 【Part 2】自定义固件 Banner（SSH 登录欢迎信息）
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
 
 🎯 TL-XDR6088 定制固件 | BY: CN2014  QQ:38663790
 🔗 管理地址: 192.168.1.1  |  用户: root  |  密码: 空
 💡 首次使用请修改默认密码，并配置 WiFi
 -----------------------------------------------------
EOF

echo "✅ 自定义 Banner 已应用"


# ============================================================================
# 🎁 【Part 2】额外自定义扩展区（可按需启用）
# ============================================================================
# echo ""
# echo "🔧 应用额外自定义配置..."

# ▸ 示例1：修改默认管理 IP（取消注释启用）
# sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
# echo "  ✓ 默认管理 IP 修改为 192.168.10.1"

# ▸ 示例2：预装额外软件包（在 .config 中添加）
# echo "CONFIG_PACKAGE_luci-app-tailscale=y" >> .config

# ▸ 示例3：添加自定义脚本到 /usr/bin
# mkdir -p files/usr/bin
# cat > files/usr/bin/mytool << 'EOF'
# #!/bin/sh
# echo "Hello from custom tool!"
# EOF
# chmod +x files/usr/bin/mytool

# ▸ 示例4：禁用不必要服务以减小固件体积
# echo "CONFIG_PACKAGE_luci-app-printer=n" >> .config


# ============================================================================
# ✅ 【Part 2】执行完成提示
# ============================================================================
echo ""
echo "================================================================"
echo "✅ DIY 脚本执行完成！(v2.1)"
echo "================================================================"
echo "📋 已应用配置："
echo "   • 第三方 Feed 源：turboacc / small / kenzo / theme"
echo "   • 预设配置：OpenClash / MosDNS / SmartDNS / opkg"
echo "   • WiFi 定制：TP-LINK_XXXX_5G/2G 自动命名"
echo "   • 主题替换：jerrykuku/luci-theme-argon (18.06)"
echo "   • 插件汉化：30+ 菜单名称精简"
echo "   • 系统优化：时区/密码/Banner/组件替换"
echo ""
echo "🚀 下一步操作："
echo "   1. make menuconfig"
echo "      → LuCI → Themes → <*> luci-theme-argon"
echo "      → LuCI → Applications → <*> luci-app-argon-config (可选)"
echo "   2. make defconfig"
echo "   3. make -j\$(nproc) V=s  # 开始编译"
echo ""
echo "💡 提示："
echo "   • GitHub Actions 用户请确保仓库包含 diy/mac80211.sh 文件"
echo "   • 本地编译请确保网络可访问 raw.githubusercontent.com"
echo "   • 如遇插件冲突，请在 menuconfig 中手动调整依赖"
echo "   • 编译失败时查看日志搜索 'ERROR' 或 'failed' 定位问题"
echo "================================================================"

exit 0
