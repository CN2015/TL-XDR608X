#!/bin/bash
#
# OpenWrt 自定义编译脚本（合并增强版 - 修复重复 Feed 问题）
# 基于 P3TERX/Actions-OpenWrt 项目修改
# 功能：添加源 / 替换插件 / WiFi定制 / 汉化 / Banner / 时区等
#
# 执行前请确保：已 clone OpenWrt 源码，并进入源码根目录
# 环境变量要求：GITHUB_WORKSPACE（Actions 环境）或手动指定 diy/ 目录路径

set -e  # 遇错立即退出，避免错误累积

#================================================================
# 📡 【Part 1】添加第三方 Feed 源（带重复检测）
# 执行时机：在 ./scripts/feeds update -a 之前
#================================================================
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

# 🎨 Argon 主题（备用）
add_feed "theme" "https://github.com/sbwml/luci-theme-argon" ""

# 📦 kenzok8 插件集合
add_feed "small" "https://github.com/kenzok8/small" ""
add_feed "kenzo" "https://github.com/kenzok8/openwrt-packages" ""

echo "✅ Feed 源添加完成"

#================================================================
# 📁 【Part 1】下载预设配置文件（来自 TL-XDR608X 项目）
#================================================================
echo "📥 下载预设配置文件..."

mkdir -p files/etc/config files/etc files/etc/opkg files/root

# OpenClash / MosDNS / SmartDNS 配置
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/openclash > files/etc/config/openclash 2>/dev/null || echo "  ⚠️ openclash 下载失败"
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/mosdns > files/etc/config/mosdns 2>/dev/null || echo "  ⚠️ mosdns 下载失败"
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/smartdns > files/etc/config/smartdns 2>/dev/null || echo "  ⚠️ smartdns 下载失败"

# opkg 包管理器配置
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/opkg.conf > files/etc/opkg.conf 2>/dev/null || echo "  ⚠️ opkg.conf 下载失败"
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/distfeeds.conf > files/etc/opkg/distfeeds.conf 2>/dev/null || echo "  ⚠️ distfeeds.conf 下载失败"

# 用户环境变量
wget -qO- https://raw.githubusercontent.com/sos801107/TL-XDR608X/refs/heads/main/etc/.profile > files/root/.profile 2>/dev/null || echo "  ⚠️ .profile 下载失败"

echo "✅ 预设配置文件下载完成"

#================================================================
# 🔄 【Part 1】更新并安装 Feed（关键步骤！）
#================================================================
echo "🔄 执行 feeds update & install..."
./scripts/feeds update -a
./scripts/feeds install -a

echo "✅ Feed 更新安装完成"
