#!/bin/bash
#
# OpenWrt 自定义编译脚本（合并增强版）
# 基于 P3TERX/Actions-OpenWrt 项目修改
# 功能：添加源 / 替换插件 / WiFi定制 / 汉化 / Banner / 时区等
#
# 执行前请确保：已 clone OpenWrt 源码，并进入源码根目录
# 环境变量要求：GITHUB_WORKSPACE（Actions 环境）或手动指定 diy/ 目录路径

set -e  # 遇错立即退出，避免错误累积

#================================================================
# 📡 【Part 1】添加第三方 Feed 源
# 执行时机：在 ./scripts/feeds update -a 之前
#================================================================
echo "📦 [Part 1] 添加第三方 Feed 源..."

# 🔧 Turbo ACC 网络加速（luci + package 分离）
echo 'src-git turboacc https://github.com/chenmozhijin/turboacc.git;luci' >> feeds.conf.default
echo 'src-git turboaccpackage https://github.com/chenmozhijin/turboacc.git;package' >> feeds.conf.default

# 🔌 VLMCSd KMS 激活服务
echo 'src-git appvlmcsd https://github.com/AutoCONFIG/luci-app-vlmcsd;master' >> feeds.conf.default

# 🎨 Argon 主题
echo 'src-git theme https://github.com/sbwml/luci-theme-argon' >> feeds.conf.default

# 📦 kenzok8 插件集合
echo 'src-git small https://github.com/kenzok8/small' >> feeds.conf.default
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >> feeds.conf.default

#================================================================
# 📁 【Part 1】下载预设配置文件（来自 TL-XDR608X 项目）
#================================================================
echo "📥 下载预设配置文件..."

mkdir -p files/etc/config files/etc files/etc/opkg files/root

# OpenClash / MosDNS / SmartDNS 配置
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/openclash > files/etc/config/openclash
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/mosdns > files/etc/config/mosdns
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/smartdns > files/etc/config/smartdns

# opkg 包管理器配置
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/opkg.conf > files/etc/opkg.conf
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/distfeeds.conf > files/etc/opkg/distfeeds.conf

# 用户环境变量
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/.profile > files/root/.profile

#================================================================
# 🔄 【Part 1】更新并安装 Feed（关键步骤！）
#================================================================
echo "🔄 执行 feeds update & install..."
./scripts/feeds update -a
./scripts/feeds install -a


#================================================================
# 📡 【Part 2】注入自定义 mac80211.sh (WiFi SSID: TP-LINK_XXXX)
#================================================================
echo "📡 应用自定义 WiFi SSID 配置 (TP-LINK_前缀)..."

# 1. 确保目标目录存在
mkdir -p package/kernel/mac80211/files/lib/wifi/

# 2. 复制 diy/mac80211.sh 覆盖源码（支持本地/Actions 双模式）
DIY_MAC_PATH="${GITHUB_WORKSPACE:-.}/diy/mac80211.sh"
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


#================================================================
# 🗑️ 【Part 2】移除冲突插件 & 替换核心组件
#================================================================
echo "🧹 清理并替换网络组件..."

# 移除旧版/冲突的科学上网插件
rm -rf feeds/small/{shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-wol,luci-app-bypass}
rm -rf feeds/luci/applications/{shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-wol,luci-app-bypass}
rm -rf feeds/luci/packages/net/{shadowsocksr-libev-ssr-check,shadowsocksr-libev-ssr-local,shadowsocksr-libev-ssr-redir,shadowsocksr-libev-ssr-server}

# 替换 packages 源中的核心组件为 small 源版本（确保新版兼容）
for pkg in xray-core mosdns v2ray-geodata v2ray-geoip sing-box chinadns-ng dns2socks dns2tcp microsocks; do
    rm -rf feeds/packages/net/$pkg
    cp -r feeds/small/$pkg feeds/packages/net/ 2>/dev/null || true
done

# 更新 FQ 插件（PassWall + OpenClash）
rm -rf feeds/luci/applications/{luci-app-passwall,luci-app-openclash}
cp -r feeds/small/luci-app-passwall feeds/luci/applications/ 2>/dev/null || true
cp -r feeds/small/luci-app-openclash feeds/luci/applications/ 2>/dev/null || true

# 替换 Argon 主题
rm -rf feeds/luci/themes/luci-theme-argon
cp -r feeds/theme/luci-theme-argon feeds/luci/themes/ 2>/dev/null || true


#================================================================
# 🌍 【Part 2】系统基础配置（时区 / 密码 / 汉化）
#================================================================
echo "⚙️ 应用系统基础配置..."

# 修改默认时区为中国上海
sed -i "s/timezone='.*'/timezone='CST-8'/g" ./package/base-files/files/bin/config_generate
sed -i "/timezone='.*'/a\\\t\t\set system.@system[-1].zonename='Asia/Shanghai'" ./package/base-files/files/bin/config_generate

# 清除默认登录密码（首次登录需自行设置）
sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings 2>/dev/null || true

# 补充中文汉化条目
echo -e "\nmsgid \"NAS\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po
echo -e "msgstr \"存储\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po

echo -e "\nmsgid \"UPnP\"" >> feeds/luci/applications/luci-app-upnp/po/zh_Hans/upnp.po
echo -e "msgstr \"即插即用\"" >> feeds/luci/applications/luci-app-upnp/po/zh_Hans/upnp.po

echo -e "\nmsgid \"Turbo ACC 网络加速\"" >> feeds/turboacc/luci-app-turboacc/po/zh-cn/turboacc.po 2>/dev/null && \
echo -e "msgstr \"网络加速\"" >> feeds/turboacc/luci-app-turboacc/po/zh-cn/turboacc.po

echo -e "\nmsgid \"Argon 主题设置\"" >> feeds/luci/applications/luci-app-argon-config/po/zh_Hans/argon-config.po 2>/dev/null && \
echo -e "msgstr \"主题设置\"" >> feeds/luci/applications/luci-app-argon-config/po/zh_Hans/argon-config.po


#================================================================
# 🎨 【Part 2】批量修改 LuCI 插件显示名称（精简中文）
#================================================================
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
    ["UPnP"]="即插即用"
    ["监控"]="带宽监视"
    ["Lucky大吉"]="全能工具"
    ["udpxy"]="电视组播"
)

# 遍历执行替换（使用 | 作为 sed 分隔符，避免 / 冲突）
for old_name in "${!NAME_MAP[@]}"; do
    new_name="${NAME_MAP[$old_name]}"
    
    # 转义特殊字符：/ & \ （避免 sed 解析错误）
    old_name_escaped=$(printf '%s\n' "$old_name" | sed 's/[\/&|]/\\&/g')
    new_name_escaped=$(printf '%s\n' "$new_name" | sed 's/[\/&|]/\\&/g')
    
    # 查找包含旧名称的文件（限制文件类型，提升效率）
    files=$(grep -rl "\"$old_name\"" ./package ./feeds 2>/dev/null | grep -E "\.(lua|po|zh-cn)$" || true)
    if [ -n "$files" ]; then
        echo "$files" | xargs -r sed -i "s|\"$old_name_escaped\"|\"$new_name_escaped\"|g"
        echo "  ✅ '$old_name' → '$new_name'"
    fi
done


#================================================================
# 🏷️ 【Part 2】自定义固件 Banner（SSH 登录欢迎信息）
#================================================================
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
EOF


#================================================================
# 🎁 【Part 2】额外自定义扩展区（可按需启用）
#================================================================
# echo "🔧 应用额外自定义配置..."

# ▸ 示例1：修改默认管理 IP（取消注释启用）
# sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

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


#================================================================
# ✅ 【Part 2】执行完成提示
#================================================================
echo ""
echo "================================================================"
echo "✅ DIY 脚本执行完成！"
echo "================================================================"
echo "📋 已应用配置："
echo "   • 第三方 Feed 源：turboacc / small / kenzo / theme"
echo "   • 预设配置：OpenClash / MosDNS / SmartDNS / opkg"
echo "   • WiFi 定制：TP-LINK_XXXX_5G/2G 自动命名"
echo "   • 插件汉化：30+ 菜单名称精简"
echo "   • 系统优化：时区/密码/Banner/组件替换"
echo ""
echo "🚀 下一步操作："
echo "   1. make menuconfig     # 按需选择插件"
echo "   2. make defconfig      # 应用配置"
echo "   3. make -j\$(nproc) V=s  # 开始编译"
echo ""
echo "💡 提示：GitHub Actions 用户请确保仓库包含 diy/mac80211.sh 文件"
echo "================================================================"
