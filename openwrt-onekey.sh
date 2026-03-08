#!/bin/bash
#
# ============================================================================
# OpenWrt 一键编译脚本（完整 DIY 版）
# 文件：openwrt-onekey.sh
# 描述：从环境准备到固件编译的全自动化脚本
# 适配：Ubuntu 20.04/22.04 + Lean 源码 + TL-XDR6088
# 作者：基于 P3TERX/Actions-OpenWrt 修改
# 许可：MIT License
# 版本：v3.0 (一键完整版)
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

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
#  输出函数
# ============================================================================
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()    { echo -e "\n${GREEN}════════════════════════════════════════${NC}"; echo -e "${GREEN}▶ $1${NC}"; echo -e "${GREEN}════════════════════════════════════════${NC}\n"; }

# ============================================================================
# 🔍 步骤 1：环境检测
# ============================================================================
check_environment() {
    step "环境检测"
    
    # 检查系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        info "操作系统：$PRETTY_NAME"
        if [[ ! "$ID" =~ ^(ubuntu|debian)$ ]]; then
            warn "非 Ubuntu/Debian 系统，可能需要手动安装依赖"
        fi
    else
        warn "无法识别操作系统"
    fi
    
    # 检查磁盘空间（需要至少 50GB）
    local free_space=$(df -BG "$WORK_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
    info "可用磁盘空间：${free_space}GB"
    if [ "${free_space:-0}" -lt 50 ]; then
        warn "磁盘空间不足 50GB，可能导致编译失败"
    fi
    
    # 检查内存
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    info "系统内存：${total_mem}GB"
    if [ "${total_mem:-0}" -lt 4 ]; then
        warn "内存小于 4GB，建议增加 swap 或减少编译线程"
    fi
    
    # 检查是否以 root 运行（不推荐）
    if [ "$EUID" -eq 0 ]; then
        warn "不建议以 root 身份运行，可能导致权限问题"
    fi
    
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
    
    # 配置 ccache（可选加速）
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
    
    # 显示源码信息
    local commit=$(git rev-parse --short HEAD)
    local branch=$(git rev-parse --abbrev-ref HEAD)
    info "源码分支：$branch"
    info "当前提交：$commit"
}

# ============================================================================
# 🔧 步骤 4：执行 DIY 配置脚本
# ============================================================================
run_diy_script() {
    step "执行 DIY 配置脚本"
    
    cd "$OPENWRT_DIR"
    
    # 检查 DIY 脚本是否存在
    if [ -f "$DIY_DIR/diy-all.sh" ]; then
        info "找到 DIY 脚本：$DIY_DIR/diy-all.sh"
        chmod +x "$DIY_DIR/diy-all.sh"
        
        # 设置环境变量供 DIY 脚本使用
        export GITHUB_WORKSPACE="$SCRIPT_DIR"
        export OPENWRT_DIR="$OPENWRT_DIR"
        
        # 执行 DIY 脚本
        "$DIY_DIR/diy-all.sh"
        
        success "DIY 配置完成"
    else
        warn "未找到 DIY 脚本 ($DIY_DIR/diy-all.sh)，跳过自定义配置"
        info "将使用默认配置编译"
        
        # 基础配置（时区等）
        sed -i "s/timezone='.*'/timezone='CST-8'/g" ./package/base-files/files/bin/config_generate
        sed -i "/timezone='.*'/a\\\t\t\set system.@system[-1].zonename='Asia/Shanghai'" ./package/base-files/files/bin/config_generate
    fi
}

# ============================================================================
# ⚙️ 步骤 5：配置编译选项
# ============================================================================
configure_build() {
    step "配置编译选项"
    
    cd "$OPENWRT_DIR"
    
    # 检查是否有预设配置文件
    if [ -f "$DIY_DIR/config.config" ]; then
        info "使用预设配置文件：$DIY_DIR/config.config"
        cp "$DIY_DIR/config.config" .config
    else
        info "生成默认配置..."
        make defconfig
    fi
    
    # 启用 ccache（如果可用）
    if [ "$ENABLE_CCACHE" = "true" ] && command -v ccache &> /dev/null; then
        echo "CONFIG_CCACHE=y" >> .config
    fi
    
    # 显示目标配置
    local target=$(grep "CONFIG_TARGET_BOARD=" .config | cut -d'"' -f2)
    local subtarget=$(grep "CONFIG_TARGET_SUBTARGET=" .config | cut -d'"' -f2)
    info "编译目标：$target/$subtarget"
    
    success "编译配置完成"
}

# ============================================================================
# 📥 步骤 6：预下载源码包
# ============================================================================
download_sources() {
    step "预下载源码包"
    
    cd "$OPENWRT_DIR"
    
    info "下载所有依赖包（这可能需要几分钟）..."
    make download -j"$COMPILE_THREADS"
    
    # 清理残缺文件
    local bad_files=$(find dl -size -1024c 2>/dev/null | wc -l)
    if [ "$bad_files" -gt 0 ]; then
        info "清理 $bad_files 个残缺文件..."
        find dl -size -1024c -exec rm -f {} \;
    fi
    
    success "源码包下载完成"
}

# ============================================================================
# 🔨 步骤 7：编译固件
# ============================================================================
compile_firmware() {
    step "编译固件"
    
    cd "$OPENWRT_DIR"
    
    info "使用 $COMPILE_THREADS 线程编译..."
    info "编译日志将输出到屏幕，也可查看 build.log"
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 开始编译（带日志记录）
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
# 📦 步骤 8：整理输出文件
# ============================================================================
organize_output() {
    step "整理输出文件"
    
    cd "$OPENWRT_DIR"
    
    # 创建输出目录
    local output_dir="$SCRIPT_DIR/output"
    mkdir -p "$output_dir"
    
    # 查找固件文件
    local firmware_files=$(find bin/targets -name "*sysupgrade.bin" 2>/dev/null)
    
    if [ -n "$firmware_files" ]; then
        info "找到固件文件："
        echo "$firmware_files" | while read -r file; do
            local filename=$(basename "$file")
            local timestamp=$(date +"%Y%m%d-%H%M%S")
            local new_name="${filename%.bin}-${timestamp}.bin"
            
            cp "$file" "$output_dir/$new_name"
            info "  ✓ 复制：$new_name"
            
            # 计算 MD5
            local md5=$(md5sum "$file" | cut -d' ' -f1)
            echo "$md5  $new_name" >> "$output_dir/md5sum.txt"
        done
        
        # 复制配置文件
        cp .config "$output_dir/build.config"
        info "  ✓ 复制：build.config"
        
        # 复制编译日志
        cp build.log "$output_dir/" 2>/dev/null && info "  ✓ 复制：build.log"
        
        success "输出文件已整理到：$output_dir"
        
        # 显示固件信息
        echo ""
        info "📋 固件信息："
        ls -lh "$output_dir"/*.bin 2>/dev/null
        echo ""
        info "🔐 MD5 校验："
        cat "$output_dir/md5sum.txt"
    else
        warn "未找到固件文件，编译可能未成功完成"
    fi
}

# ============================================================================
# 📊 步骤 9：生成编译报告
# ============================================================================
generate_report() {
    step "生成编译报告"
    
    local report_file="$SCRIPT_DIR/output/build-report.txt"
    
    cat > "$report_file" << EOF
================================================================================
OpenWrt 编译报告
================================================================================
编译时间：$(date +"%Y-%m-%d %H:%M:%S")
源码仓库：$REPO_URL
源码分支：$REPO_BRANCH
源码提交：$(cd "$OPENWRT_DIR" && git rev-parse --short HEAD)
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
EOF
    
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
    cat << EOF
OpenWrt 一键编译脚本 v3.0

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

EOF
}

# ============================================================================
# 🎯 主函数
# ============================================================================
main() {
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--clean)
                CLEAN_BUILD="true"
                shift
                ;;
            -s|--skip-deps)
                SKIP_DEPS="true"
                shift
                ;;
            -t|--threads)
                COMPILE_THREADS="$2"
                shift 2
                ;;
            -n|--no-compile)
                NO_COMPILE="true"
                shift
                ;;
            -r|--repo)
                REPO_URL="$2"
                shift 2
                ;;
            -b|--branch)
                REPO_BRANCH="$2"
                shift 2
                ;;
            *)
                error "未知参数：$1 (使用 -h 查看帮助)"
                ;;
        esac
    done
    
    # 显示欢迎信息
    cat << EOF
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                    OpenWrt 一键编译脚本 v3.0                                 ║
║                    基于 Lean 源码 + 完整 DIY 配置                            ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

工作目录：$WORK_DIR
源码仓库：$REPO_URL ($REPO_BRANCH)
编译线程：$COMPILE_THREADS
CCache：$ENABLE_CCACHE

EOF
    
    # 执行各步骤
    check_environment
    [ "$SKIP_DEPS" != "true" ] && install_dependencies
    clone_source
    run_diy_script
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
