#!/bin/bash
#
# ============================================================================
# OpenWrt 一键编译脚本（完整整合修复版）
# 文件：openwrt-onekey.sh
# 描述：从环境准备到固件编译的全自动化脚本（含所有修复功能）
# 适配：Ubuntu 20.04/22.04 + Lean 源码 + TL-XDR6088
# 作者：基于 P3TERX/Actions-OpenWrt 修改
# 许可：MIT License
# 版本：v3.1 (整合修复版 - 内联所有 DIY 逻辑)
# ============================================================================

set -e  # 遇错立即退出

# ============================================================================
# 📋 全局配置（可自定义）
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/openwrt-build}"
OPENWRT_DIR="$WORK_DIR/openwrt"
DIY_DIR="$SCRIPT_DIR/diy"

# 源码配置
REPO_URL="${REPO_URL:-https://github.com/coolsnowwolf/lede}"
REPO_BRANCH="${REPO_BRANCH:-master}"

# 设备配置
TARGET_BOARD="mediatek"
TARGET_SUBTARGET="filogic"
DEVICE_PROFILE="tplink_tl-xdr6088"

# 编译配置
COMPILE_THREADS="${COMPILE_THREADS:-$(nproc)}"
ENABLE_CCACHE="${ENABLE_CCACHE:-true}"

# 网络配置（超时重试）
WGET_CMD="wget -qO- --timeout=30 --tries=3"
GIT_CMD="git clone --depth=1 --timeout=30"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
#  输出函数
# ============================================================================
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()    { echo -e "\n${GREEN}════════════════════════════════════════${NC}"; echo -e "${GREEN}▶ $1${NC}"; echo -e "${GREEN}════════════════════════════════════════${NC}\n"; }

# ============================================================================
# 🔧 DIY 核心功能：添加 Feed 源（带重复检测）
# ============================================================================
diy_add_feeds() {
    info "添加第三方 Feed 源..."
    
    # 辅助函数：检查并添加 Feed 源（避免重复）
    add_feed() {
        local feed_name="$1"
        local feed_url="$2"
        local feed_branch="$3"
        
        if grep -q "^src-git $feed_name " feeds.conf.default 2>/dev/null; then
            echo "  ℹ️  Feed '$feed_name' 已存在，跳过"
        else
            if [ -n "$feed_branch" ]; then
                echo "src-git $feed_name $feed_url;$feed_branch" >> feeds.conf.default
            else
                echo "src-git $feed_name $feed_url" >> feeds.conf.default
            fi
            echo "  ✅ 已添加: $feed_name"
        fi
    }
    
    # Turbo ACC 网络加速
    add_feed "turboacc" "https://github.com/chenmozhijin/turboacc.git" "luci"
    add_feed "turboaccpackage" "https://github.com/chenmozhijin/turboacc.git" "package"
    
    # VLMCSd KMS 激活
    add_feed "appvlmcsd" "https://github.com/AutoCONFIG/luci-app-vlmcsd" "master"
    
    # kenzok8 插件集合
    add_feed "small" "https://github.com/kenzok8/small" ""
    add_feed "kenzo" "https://github.com/kenzok8/openwrt-packages" ""
    
    success "Feed 源添加完成"
}

# ============================================================================
# 🔧 DIY 核心功能：下载预设配置文件
# ============================================================================
diy_download_configs() {
    info "下载预设配置文件..."
    
    mkdir -p files/etc/config files/etc files/etc/opkg files/root
    
    # 下载配置（带超时重试 + 失败提示）
    $WGET_CMD https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/openclash > files/etc/config/openclash 2>/dev/null && echo "  ✓ openclash" || echo "  ✗ openclash"
    $WGET_CMD https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/mosdns > files/etc/config/mosdns 2>/dev/null && echo "  ✓ mosdns" || echo "  ✗ mosdns"
    $WGET_CMD https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/smartdns > files/etc/config/smartdns 2>/dev/null && echo "  ✓ smartdns" || echo "  ✗ smartdns"
    $WGET_CMD https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/opkg.conf > files/etc/opkg.conf 2>/dev/null && echo "  ✓ opkg.conf" || echo "  ✗ opkg.conf"
    $WGET_CMD https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/distfeeds.conf > files/etc/opkg/distfeeds.conf 2>/dev/null && echo "  ✓ distfeeds.conf" || echo "  ✗ distfeeds.conf"
    $WGET_CMD https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/.profile > files/root/.profile 2>/dev/null && echo "  ✓ .profile" || echo "  ✗ .profile"
    
    success "配置文件下载完成"
}

# ============================================================================
# 🔧 DIY 核心功能：自定义 WiFi SSID (TP-LINK_XXXX)
# ============================================================================
diy_custom_wifi() {
    info "应用自定义 WiFi SSID 配置..."
    
    # 1. 覆盖 mac80211.sh（如果存在自定义文件）
    mkdir -p package/kernel/mac80211/files/lib/wifi/
    if [ -f "$DIY_DIR/mac80211.sh" ]; then
        cp -f "$DIY_DIR/mac80211.sh" package/kernel/mac80211/files/lib/wifi/mac80211.sh
        chmod +x package/kernel/mac80211/files/lib/wifi/mac80211.sh
        echo "  ✅ mac80211.sh 已覆盖"
    else
        echo "  ℹ️  未找到 diy/mac80211.sh，使用默认配置"
    fi
    
    # 2. 添加 uci-defaults 首启脚本（双重保障）
    mkdir -p files/etc/uci-defaults/
    cat > files/etc/uci-defaults/99-wifi-ssid <<- 'WIFIEOF'
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
WIFIEOF
    chmod +x files/etc/uci-defaults/99-wifi-ssid
    echo "  ✅ uci-defaults 脚本已添加"
    echo "  🎯 WiFi 名称: TP-LINK_XXXX_5G / TP-LINK_XXXX_2G"
    
    success "WiFi 定制完成"
}

# ============================================================================
# 🔧 DIY 核心功能：替换插件 & 核心组件
# ============================================================================
diy_replace_components() {
    info "清理并替换网络组件..."
    
    # 移除冲突插件
    rm -rf feeds/small/{shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-wol,luci-app-bypass} 2>/dev/null || true
    rm -rf feeds/luci/applications/{shadowsocksr-libev,shadowsocks-rust,luci-app-ssr-plus,luci-i18n-ssr-plus-zh-cn,luci-app-wol,luci-app-bypass} 2>/dev/null || true
    
    # 替换核心组件为 small 源版本
    for pkg in xray-core mosdns v2ray-geodata v2ray-geoip sing-box chinadns-ng dns2socks dns2tcp microsocks; do
        rm -rf feeds/packages/net/$pkg 2>/dev/null || true
        cp -r feeds/small/$pkg feeds/packages/net/ 2>/dev/null && echo "  ✓ $pkg" || true
    done
    
    # 更新代理插件
    rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true
    rm -rf feeds/luci/applications/luci-app-openclash 2>/dev/null || true
    cp -r feeds/small/luci-app-passwall feeds/luci/applications/ 2>/dev/null && echo "  ✓ passwall" || true
    cp -r feeds/small/luci-app-openclash feeds/luci/applications/ 2>/dev/null && echo "  ✓ openclash" || true
    
    success "组件替换完成"
}

# ============================================================================
# 🔧 DIY 核心功能：替换 Argon 主题为 jerrykuku 官方 18.06
# ============================================================================
diy_replace_argon_theme() {
    info "应用 jerrykuku/luci-theme-argon (18.06)..."
    
    # 清理旧版本
    rm -rf feeds/luci/themes/luci-theme-argon 2>/dev/null || true
    rm -rf package/lean/luci-theme-argon 2>/dev/null || true
    rm -rf package/lean/luci-app-argon-config 2>/dev/null || true
    
    # 克隆官方主题（18.06 分支）
    THEME_DIR="package/lean/luci-theme-argon"
    [ ! -d "package/lean" ] && THEME_DIR="package/themes/luci-theme-argon" && mkdir -p package/themes
    
    if $GIT_CMD https://github.com/jerrykuku/luci-theme-argon.git "$THEME_DIR" 2>/dev/null; then
        echo "  ✅ 已克隆: luci-theme-argon (18.06)"
    else
        echo "  ⚠️  克隆失败，请检查网络"
    fi
    
    # 克隆配置插件（可选）
    CONFIG_DIR="package/lean/luci-app-argon-config"
    [ ! -d "package/lean" ] && CONFIG_DIR="package/luci-app-argon-config"
    $GIT_CMD https://github.com/jerrykuku/luci-app-argon-config.git "$CONFIG_DIR" 2>/dev/null && \
        echo "  ✅ 已克隆: luci-app-argon-config" || \
        echo "  ℹ️  未克隆配置插件，可手动启用"
    
    echo "  💡 提示: menuconfig → LuCI → Themes → <*> luci-theme-argon"
    success "主题替换完成"
}

# ============================================================================
# 🔧 DIY 核心功能：系统基础配置（时区/密码/汉化）
# ============================================================================
diy_system_config() {
    info "应用系统基础配置..."
    
    # 时区设置
    sed -i "s/timezone='.*'/timezone='CST-8'/g" ./package/base-files/files/bin/config_generate
    sed -i "/timezone='.*'/a\\\t\t\set system.@system[-1].zonename='Asia/Shanghai'" ./package/base-files/files/bin/config_generate
    echo "  ✓ 时区: Asia/Shanghai"
    
    # 清除默认密码
    sed -i '/V4UetPzk$CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings 2>/dev/null || true
    echo "  ✓ 默认密码已清除"
    
    # 基础汉化（安全写入）
    echo -e "\nmsgid \"NAS\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po 2>/dev/null || true
    echo -e "msgstr \"存储\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po 2>/dev/null || true
    echo -e "\nmsgid \"UPnP\"" >> feeds/luci/applications/luci-app-upnp/po/zh_Hans/upnp.po 2>/dev/null || true
    echo -e "msgstr \"即插即用\"" >> feeds/luci/applications/luci-app-upnp/po/zh_Hans/upnp.po 2>/dev/null || true
    
    # Turbo ACC 汉化（动态查找路径）
    TURBO_PO=$(find ./feeds ./package -name "turboacc.po" -path "*/zh*" 2>/dev/null | head -n1)
    if [ -n "$TURBO_PO" ] && [ -w "$TURBO_PO" ]; then
        grep -q "msgid \"Turbo ACC 网络加速\"" "$TURBO_PO" 2>/dev/null || {
            echo -e "\nmsgid \"Turbo ACC 网络加速\"" >> "$TURBO_PO"
            echo -e "msgstr \"网络加速\"" >> "$TURBO_PO"
            echo "  ✓ Turbo ACC 汉化"
        }
    fi
    
    # Argon Config 汉化（动态查找 + 防重复）
    ARGON_PO=$(find ./package ./feeds -name "argon-config.po" -path "*/zh*" 2>/dev/null | head -n1)
    if [ -n "$ARGON_PO" ] && [ -w "$ARGON_PO" ]; then
        grep -q "msgid \"Argon 主题设置\"" "$ARGON_PO" 2>/dev/null || {
            echo -e "\nmsgid \"Argon 主题设置\"" >> "$ARGON_PO"
            echo -e "msgstr \"主题设置\"" >> "$ARGON_PO"
            echo "  ✓ Argon Config 汉化"
        }
    fi
    
    success "系统配置完成"
}

# ============================================================================
# 🔧 DIY 核心功能：批量插件名称汉化（精简中文）
# ============================================================================
diy_translate_names() {
    info "应用插件名称汉化/精简..."
    
    # 定义替换规则
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
    
    # 遍历替换
    for old_name in "${!NAME_MAP[@]}"; do
        new_name="${NAME_MAP[$old_name]}"
        old_esc=$(printf '%s\n' "$old_name" | sed 's/[\/&|\\]/\\&/g')
        new_esc=$(printf '%s\n' "$new_name" | sed 's/[\/&|\\]/\\&/g')
        
        files=$(grep -rl "\"$old_name\"" ./package ./feeds 2>/dev/null | grep -E "\.(lua|po|zh-cn)$" || true)
        if [ -n "$files" ]; then
            echo "$files" | xargs -r sed -i "s|\"$old_esc\"|\"$new_esc\"|g" 2>/dev/null && \
            echo "  ✅ '$old_name' → '$new_name'"
        fi
    done
    
    success "插件汉化完成"
}

# ============================================================================
# 🔧 DIY 核心功能：自定义 Banner
# ============================================================================
diy_custom_banner() {
    info "应用自定义 Banner..."
    
    cat > package/base-files/files/etc/banner << 'BANNEREOF'
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
BANNEREOF
    
    echo "  ✅ 自定义 Banner 已应用"
    success "Banner 定制完成"
}

# ============================================================================
# 🔧 DIY 主函数：整合所有 DIY 功能
# ============================================================================
run_diy_all() {
    step "执行 DIY 配置（内联整合版）"
    cd "$OPENWRT_DIR"
    
    # 按顺序执行所有 DIY 功能
    diy_add_feeds
    diy_download_configs
    
    # 更新 feeds（关键步骤）
    info "执行 feeds update & install..."
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    success "Feed 更新完成"
    
    # 继续执行其他 DIY 功能
    diy_custom_wifi
    diy_replace_components
    diy_replace_argon_theme
    diy_system_config
    diy_translate_names
    diy_custom_banner
    
    success "═══════════════════════════════════════"
    success "         所有 DIY 配置已完成！          "
    success "═══════════════════════════════════════"
}

# ============================================================================
# 🔍 步骤 1：环境检测
# ============================================================================
check_environment() {
    step "环境检测"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        info "操作系统：$PRETTY_NAME"
        if [[ ! "$ID" =~ ^(ubuntu|debian)$ ]]; then
            warn "非 Ubuntu/Debian 系统，可能需要手动安装依赖"
        fi
    else
        warn "无法识别操作系统"
    fi
    
    local free_space=$(df -BG "$WORK_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
    info "可用磁盘空间：${free_space}GB"
    [ "${free_space:-0}" -lt 50 ] && warn "磁盘空间不足 50GB，可能导致编译失败"
    
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    info "系统内存：${total_mem}GB"
    [ "${total_mem:-0}" -lt 4 ] && warn "内存小于 4GB，建议增加 swap 或减少编译线程"
    
    [ "$EUID" -eq 0 ] && warn "不建议以 root 身份运行"
    
    success "环境检测完成"
}

# ============================================================================
#  步骤 2：安装编译依赖
# ============================================================================
install_dependencies() {
    step "安装编译依赖"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                info "更新包列表..."
                sudo apt update -qq
                
                info "安装编译依赖..."
                sudo apt install -y -qq \
                    build-essential clang flex bison g++ gawk \
                    gcc-multilib g++-multilib gettext git libncurses5-dev \
                    libssl-dev python3 python3-pip python3-setuptools \
                    rsync unzip zlib1g-dev file wget curl jq time \
                    ccache libelf-dev libglib2.0-dev libgmp3-dev \
                    libmpc-dev libmpfr-dev libpython3-dev libreadline-dev \
                    libtool lrzsz mkisofs msmtp ninja-build p7zip-full \
                    patch pkgconf squashfs-tools subversion swig \
                    texinfo uglifyjs upx-ucl xmlto xxd
                    
                success "依赖安装完成"
                ;;
            *)
                warn "未知系统，请手动安装依赖"
                ;;
        esac
    else
        warn "无法识别系统，请手动安装依赖"
    fi
    
    if [ "$ENABLE_CCACHE" = "true" ] && command -v ccache &> /dev/null; then
        info "配置 ccache 加速..."
        export PATH="/usr/lib/ccache:$PATH"
        echo "export PATH=\"/usr/lib/ccache:\$PATH\"" >> ~/.bashrc
        success "ccache 已配置"
    fi
}

# ============================================================================
# 📥 步骤 3：克隆 OpenWrt 源码
# ============================================================================
clone_source() {
    step "克隆 OpenWrt 源码"
    
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    if [ -d "openwrt" ]; then
        info "检测到已有源码，尝试更新..."
        cd openwrt
        git fetch --all
        git reset --hard origin/$REPO_BRANCH
        success "源码更新完成"
    else
        info "克隆源码：$REPO_URL ($REPO_BRANCH)..."
        git clone -b "$REPO_BRANCH" --single-branch "$REPO_URL" openwrt
        success "源码克隆完成"
    fi
    
    cd "$OPENWRT_DIR"
    local commit=$(git rev-parse --short HEAD)
    local branch=$(git rev-parse --abbrev-ref HEAD)
    info "源码分支：$branch"
    info "当前提交：$commit"
}

# ============================================================================
# ⚙️ 步骤 4：配置编译选项
# ============================================================================
configure_build() {
    step "配置编译选项"
    
    cd "$OPENWRT_DIR"
    
    if [ -f "$DIY_DIR/config.config" ]; then
        info "使用预设配置文件：$DIY_DIR/config.config"
        cp "$DIY_DIR/config.config" .config
    else
        info "生成默认配置..."
        make defconfig
    fi
    
    if [ "$ENABLE_CCACHE" = "true" ] && command -v ccache &> /dev/null; then
        echo "CONFIG_CCACHE=y" >> .config
    fi
    
    local target=$(grep "CONFIG_TARGET_BOARD=" .config 2>/dev/null | cut -d'"' -f2 || echo "unknown")
    local subtarget=$(grep "CONFIG_TARGET_SUBTARGET=" .config 2>/dev/null | cut -d'"' -f2 || echo "unknown")
    info "编译目标：$target/$subtarget"
    
    success "编译配置完成"
}

# ============================================================================
# 📥 步骤 5：预下载源码包
# ============================================================================
download_sources() {
    step "预下载源码包"
    
    cd "$OPENWRT_DIR"
    info "下载所有依赖包（这可能需要几分钟）..."
    make download -j"$COMPILE_THREADS"
    
    local bad_files=$(find dl -size -1024c 2>/dev/null | wc -l)
    if [ "$bad_files" -gt 0 ]; then
        info "清理 $bad_files 个残缺文件..."
        find dl -size -1024c -exec rm -f {} \;
    fi
    
    success "源码包下载完成"
}

# ============================================================================
# 🔨 步骤 6：编译固件
# ============================================================================
compile_firmware() {
    step "编译固件"
    
    cd "$OPENWRT_DIR"
    info "使用 $COMPILE_THREADS 线程编译..."
    info "编译日志将输出到屏幕，也可查看 build.log"
    
    local start_time=$(date +%s)
    
    if make -j"$COMPILE_THREADS" V=s 2>&1 | tee build.log; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local hours=$((duration / 3600))
        local minutes=$(((duration % 3600) / 60))
        local seconds=$((duration % 60))
        success "编译成功！耗时：${hours}h ${minutes}m ${seconds}s"
    else
        error "编译失败！请查看 build.log 排查错误"
    fi
}

# ============================================================================
# 📦 步骤 7：整理输出文件
# ============================================================================
organize_output() {
    step "整理输出文件"
    
    cd "$OPENWRT_DIR"
    local output_dir="$SCRIPT_DIR/output"
    mkdir -p "$output_dir"
    
    local firmware_files=$(find bin/targets -name "*sysupgrade.bin" 2>/dev/null)
    
    if [ -n "$firmware_files" ]; then
        info "找到固件文件："
        echo "$firmware_files" | while read -r file; do
            local filename=$(basename "$file")
            local timestamp=$(date +"%Y%m%d-%H%M%S")
            local new_name="${filename%.bin}-${timestamp}.bin"
            cp "$file" "$output_dir/$new_name"
            info "  ✓ 复制：$new_name"
            local md5=$(md5sum "$file" | cut -d' ' -f1)
            echo "$md5  $new_name" >> "$output_dir/md5sum.txt"
        done
        
        cp .config "$output_dir/build.config"
        info "  ✓ 复制：build.config"
        cp build.log "$output_dir/" 2>/dev/null && info "  ✓ 复制：build.log"
        
        success "输出文件已整理到：$output_dir"
        
        echo ""
        info "📋 固件信息："
        ls -lh "$output_dir"/*.bin 2>/dev/null
        echo ""
        info "🔐 MD5 校验："
        cat "$output_dir/md5sum.txt" 2>/dev/null || true
    else
        warn "未找到固件文件，编译可能未成功完成"
    fi
}

# ============================================================================
# 📊 步骤 8：生成编译报告
# ============================================================================
generate_report() {
    step "生成编译报告"
    
    local report_file="$SCRIPT_DIR/output/build-report.txt"
    
    cat > "$report_file" << REPORTEOF
================================================================================
OpenWrt 编译报告
================================================================================
编译时间：$(date +"%Y-%m-%d %H:%M:%S")
源码仓库：$REPO_URL
源码分支：$REPO_BRANCH
源码提交：$(cd "$OPENWRT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "N/A")
编译主机：$(hostname)
系统版本：$(uname -a)
编译线程：$COMPILE_THREADS
CCache 加速：$ENABLE_CCACHE
================================================================================

固件文件：
$(ls -lh "$SCRIPT_DIR/output"/*.bin 2>/dev/null || echo "无")

MD5 校验：
$(cat "$SCRIPT_DIR/output/md5sum.txt" 2>/dev/null || echo "无")

================================================================================
编译完成！
================================================================================
REPORTEOF
    
    success "编译报告已生成：$report_file"
    cat "$report_file"
}

# ============================================================================
# 🧹 清理函数
# ============================================================================
cleanup() {
    if [ -n "$CLEAN_BUILD" ] && [ "$CLEAN_BUILD" = "true" ]; then
        step "清理编译环境"
        cd "$OPENWRT_DIR"
        make dirclean
        success "清理完成"
    fi
}

# ============================================================================
# ❓ 帮助信息
# ============================================================================
show_help() {
    cat << HELPEOF
OpenWrt 一键编译脚本 v3.1 (整合修复版)

用法：$0 [选项]

选项:
  -h, --help              显示此帮助信息
  -c, --clean             编译前清理环境（dirclean）
  -s, --skip-deps         跳过依赖安装（已安装时使用）
  -t, --threads NUM       设置编译线程数（默认：CPU 核心数）
  -n, --no-compile        只配置不编译（用于测试配置）
  -r, --repo URL          指定源码仓库 URL
  -b, --branch NAME       指定源码分支名称

示例:
  $0                      # 完整编译
  $0 -c -t 4              # 清理后使用 4 线程编译
  $0 --skip-deps          # 跳过依赖安装
  $0 -n                   # 只配置不编译

环境变量:
  WORK_DIR                工作目录（默认：脚本所在目录/openwrt-build）
  COMPILE_THREADS         编译线程数
  ENABLE_CCACHE           是否启用 ccache（true/false）

整合功能:
  ✓ 重复 Feed 源检测
  ✓ 汉化路径动态查找
  ✓ 安全写入（防报错）
  ✓ 网络超时重试
  ✓ jerrykuku Argon 主题 (18.06)
  ✓ WiFi SSID 自动定制 (TP-LINK_XXXX)
  ✓ 30+ 插件名称精简汉化
  ✓ 自定义 Banner/时区/密码

HELPEOF
}

# ============================================================================
# 🎯 主函数
# ============================================================================
main() {
    CLEAN_BUILD="false"
    SKIP_DEPS="false"
    NO_COMPILE="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_help; exit 0 ;;
            -c|--clean) CLEAN_BUILD="true"; shift ;;
            -s|--skip-deps) SKIP_DEPS="true"; shift ;;
            -t|--threads) COMPILE_THREADS="$2"; shift 2 ;;
            -n|--no-compile) NO_COMPILE="true"; shift ;;
            -r|--repo) REPO_URL="$2"; shift 2 ;;
            -b|--branch) REPO_BRANCH="$2"; shift 2 ;;
            *) error "未知参数：$1 (使用 -h 查看帮助)" ;;
        esac
    done
    
    cat << BANNER
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║              OpenWrt 一键编译脚本 v3.1 (整合修复版)                          ║
║              内联所有 DIY 功能 · 无需额外脚本                                ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

工作目录：$WORK_DIR
源码仓库：$REPO_URL ($REPO_BRANCH)
编译线程：$COMPILE_THREADS
CCache：$ENABLE_CCACHE

BANNER
    
    check_environment
    [ "$SKIP_DEPS" != "true" ] && install_dependencies
    clone_source
    run_diy_all
    configure_build
    
    if [ "$NO_COMPILE" != "true" ]; then
        download_sources
        compile_firmware
        organize_output
        generate_report
        cleanup
    else
        success "配置完成！跳过编译步骤"
        info "如需编译，请运行：cd $OPENWRT_DIR && make -j$COMPILE_THREADS"
    fi
    
    echo ""
    success "═══════════════════════════════════════════════════════════"
    success "                    全部完成！                             "
    success "═══════════════════════════════════════════════════════════"
    echo ""
    info "固件位置：$SCRIPT_DIR/output/"
    info "编译日志：$OPENWRT_DIR/build.log"
    info "配置文件：$SCRIPT_DIR/output/build.config"
    echo ""
}

# ============================================================================
# 🚀 脚本入口
# ============================================================================
main "$@"
