#!/bin/bash
# =================================================================
# DIY Script for TL-XDR6088 LEDE Firmware
# 功能: 自定义配置 + WiFi SSID 注入
# =================================================================

# 🔧 LUCI 版本切换
sed -i 's/openwrt-23.05/openwrt-24.10/g' ./feeds.conf.default

# =================================================================
# 📦 下载配置文件到 files 目录
# =================================================================
mkdir -p files/etc/config
wget -qO- https://raw.githubusercontent.com/liandu2024/clash/refs/heads/main/main_router/openclash   > files/etc/config/openclash
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/mosdns   > files/etc/config/mosdns
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/smartdns   > files/etc/config/smartdns

mkdir -p files/etc
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/opkg.conf   > files/etc/opkg.conf
mkdir -p files/etc/opkg
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/distfeeds.conf   > files/etc/opkg/distfeeds.conf

mkdir -p files/root
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/.profile   > files/root/.profile

# =================================================================
# ⚙️ 系统基础配置
# =================================================================
# 修改默认 IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/192.168.1.1/g" ./package/base-files/files/bin/config_generate
# 修改默认主机名
sed -i "s/hostname='.*'/hostname='LEDE'/g" ./package/base-files/files/bin/config_generate
# 修改默认时区
sed -i "s/timezone='.*'/timezone='CST-8'/g" ./package/base-files/files/bin/config_generate
sed -i "/timezone='.*'/a\\\t\t\set system.@system[-1].zonename='Asia/Shanghai'" ./package/base-files/files/bin/config_generate
# TTYD 菜单修正
sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
# 主题切换
sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile
# 作者信息
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By sos07'/g" package/base-files/files/etc/openwrt_release

# =================================================================
# 🗑️ 移除冲突包
# =================================================================
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,adguardhome,mosdns,v2ray-geodata,v2ray-geoip,chinadns-ng,dns2socks,dns2tcp,microsocks,alist}
rm -rf feeds/packages/utils/v2dat
rm -rf feeds/third_party/{luci-app-LingTiGameAcc,luci-app-smartdns,smartdns}
rm -rf feeds/small/{luci-app-openclash,sing-box,luci-app-passwall,shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-wol,luci-app-bypass,luci-app-argon-config,luci-theme-argon}
rm -rf feeds/luci/applications/{luci-app-tailscale,luci-app-turboacc,luci-app-alist,shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-wol,luci-app-bypass,luci-app-argon-config,luci-theme-argon}
rm -rf feeds/luci/packages/net/{shadowsocksr-libev-ssr-check,shadowsocksr-libev-ssr-local,shadowsocksr-libev-ssr-redir,shadowsocksr-libev-ssr-server}
rm -rf feeds/kenzo/{luci-app-argon-config,luci-theme-argon}
rm -rf feeds/third/{luci-app-argon-config,luci-theme-argon}
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/packages/libs/libfido2
rm -rf feeds/packages/net/shadowsocks-libev

# =================================================================
# 📦 稀疏克隆函数
# =================================================================
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

function merge_package() {
    if [[ $# -lt 3 ]]; then
        echo "Syntax error: [$#] [$*]" >&2
        return 1
    fi
    trap 'rm -rf "$tmpdir"' EXIT
    branch="$1" curl="$2" target_dir="$3" && shift 3
    rootdir="$PWD"
    localdir="$target_dir"
    [ -d "$localdir" ] || mkdir -p "$localdir"
    tmpdir="$(mktemp -d)" || exit 1
    git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$curl" "$tmpdir"
    cd "$tmpdir"
    git sparse-checkout init --cone
    git sparse-checkout set "$@"
    for folder in "$@"; do
        mv -f "$folder" "$rootdir/$localdir"
    done
    cd "$rootdir"
}

# =================================================================
# 📦 添加第三方插件
# =================================================================
git_sparse_clone main https://github.com/Openwrt-Passwall/openwrt-passwall   luci-app-passwall
git_sparse_clone dev https://github.com/vernesong/OpenClash   luci-app-openclash

# Go 1.24.2 依赖
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang   -b 26.x feeds/packages/lang/golang

# =================================================================
# 🔧 应用补丁
# =================================================================
pushd feeds/luci
   curl -s https://raw.githubusercontent.com/oppen321/path/refs/heads/main/Firewall/0001-luci-mod-status-firewall-disable-legacy-firewall-rul.patch   | patch -p1
popd

pushd
   curl -sSL https://raw.githubusercontent.com/Jaykwok2999/turboacc/luci/add_turboacc.sh   -o add_turboacc.sh && bash add_turboacc.sh
popd

# =================================================================
# 🔄 更新 feeds
# =================================================================
./scripts/feeds update -a
./scripts/feeds install -a

# =================================================================
# 📡 【新增】注入自定义 mac80211.sh (WiFi SSID: TP-LINK_XXXX)
# =================================================================
echo "🔧 应用自定义 WiFi SSID 配置 (TP-LINK_前缀)..."

# 1. 确保目标目录存在
mkdir -p package/kernel/mac80211/files/lib/wifi/

# 2. 复制 diy/mac80211.sh 覆盖源码
if [ -f "$GITHUB_WORKSPACE/diy/mac80211.sh" ]; then
    cp -f "$GITHUB_WORKSPACE/diy/mac80211.sh" package/kernel/mac80211/files/lib/wifi/mac80211.sh
    chmod +x package/kernel/mac80211/files/lib/wifi/mac80211.sh
    echo "✅ mac80211.sh 已覆盖: package/kernel/mac80211/files/lib/wifi/"
else
    echo "⚠️ 警告: diy/mac80211.sh 未找到，将使用默认 WiFi 配置"
fi

# 3. 添加 uci-defaults 首启脚本（双重保障）
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
