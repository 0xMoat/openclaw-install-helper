#!/bin/bash
#
# OpenClaw 一键安装脚本 (macOS)
# 自动安装 Git, Node.js (LTS), OpenClaw 及飞书插件
# 无需重启终端
#

set -e

# ============================================================
# 颜色定义
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

print_step() { echo -e "\n${CYAN}[步骤]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }

# ============================================================
# NPM 镜像源测速与选择（并发测试）
# ============================================================
ORIGINAL_NPM_REGISTRY=""
SELECTED_NPM_REGISTRY=""

# 获取毫秒级时间戳（兼容 macOS 和 Linux）
get_timestamp_ms() {
    if command -v gdate &> /dev/null; then
        gdate +%s%3N
    elif command -v python3 &> /dev/null; then
        python3 -c 'import time; print(int(time.time() * 1000))'
    elif command -v python &> /dev/null; then
        python -c 'import time; print(int(time.time() * 1000))'
    else
        # 降级为秒级（乘以1000模拟毫秒）
        echo $(($(date +%s) * 1000))
    fi
}

# 测试单个 NPM 镜像源并记录响应时间
# 参数: registry_url output_file name
test_npm_registry_with_timing() {
    local registry_url="$1"
    local output_file="$2"
    local name="$3"

    local start_time=$(get_timestamp_ms)

    # 使用 curl 测试镜像源响应时间（获取一个小包的元数据）
    if curl -s --connect-timeout 5 --max-time 8 "${registry_url}lodash" > /dev/null 2>&1; then
        local end_time=$(get_timestamp_ms)
        local elapsed=$((end_time - start_time))
        echo "${elapsed}|${registry_url}|${name}" > "$output_file"
    else
        echo "failed|${registry_url}|${name}" > "$output_file"
    fi
}

# 并发选择最快的可用 NPM 镜像源
# 返回: 设置 SELECTED_NPM_REGISTRY 变量
select_best_npm_registry() {
    print_step "并发测试 NPM 镜像源..." >&2

    local registries=(
        "https://registry.npmmirror.com/"
        "https://mirrors.cloud.tencent.com/npm/"
        "https://mirrors.huaweicloud.com/repository/npm/"
        "https://registry.npmjs.org/"
    )

    local registry_names=(
        "淘宝源(阿里)"
        "腾讯云源"
        "华为云源"
        "官方源(npmjs)"
    )

    # 保存原始镜像源配置
    ORIGINAL_NPM_REGISTRY=$(npm config get registry 2>/dev/null || echo "")

    # 创建临时目录存放测试结果
    local tmp_dir=$(mktemp -d)
    local pids=()

    # 并发启动所有测试
    echo "  正在并发测试 ${#registries[@]} 个镜像源..." >&2
    for i in "${!registries[@]}"; do
        local registry="${registries[$i]}"
        local name="${registry_names[$i]}"
        test_npm_registry_with_timing "$registry" "$tmp_dir/result_$i" "$name" &
        pids+=($!)
    done

    # 等待所有测试完成（最多等待 10 秒）
    local wait_count=0
    while [[ $wait_count -lt 20 ]]; do
        local all_done=true
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_done=false
                break
            fi
        done
        if $all_done; then
            break
        fi
        sleep 0.5
        ((wait_count++))
    done

    # 收集结果并排序
    local results=()
    for i in "${!registries[@]}"; do
        local result_file="$tmp_dir/result_$i"
        if [[ -f "$result_file" ]]; then
            local content=$(cat "$result_file")
            local timing=$(echo "$content" | cut -d'|' -f1)
            local url=$(echo "$content" | cut -d'|' -f2)
            local name=$(echo "$content" | cut -d'|' -f3)

            if [[ "$timing" != "failed" ]]; then
                echo -e "  ${name}: ${GREEN}${timing}ms${NC}" >&2
                results+=("$timing|$url|$name")
            else
                echo -e "  ${name}: ${RED}不可用${NC}" >&2
            fi
        fi
    done

    # 清理临时文件
    rm -rf "$tmp_dir"

    # 按响应时间排序，选择最快的
    if [[ ${#results[@]} -gt 0 ]]; then
        # 使用 sort 按数字排序
        local best=$(printf '%s\n' "${results[@]}" | sort -t'|' -k1 -n | head -1)
        local best_url=$(echo "$best" | cut -d'|' -f2)
        local best_name=$(echo "$best" | cut -d'|' -f3)
        local best_time=$(echo "$best" | cut -d'|' -f1)

        print_success "已选择最快 NPM 镜像源: $best_name (${best_time}ms)" >&2
        SELECTED_NPM_REGISTRY="$best_url"
        npm config set registry "$best_url" 2>/dev/null || true
    else
        print_warning "所有镜像源均不可用，使用淘宝镜像源" >&2
        SELECTED_NPM_REGISTRY="https://registry.npmmirror.com/"
        npm config set registry "https://registry.npmmirror.com/" 2>/dev/null || true
    fi
}

restore_npm_registry() {
    if [[ -n "$ORIGINAL_NPM_REGISTRY" && "$ORIGINAL_NPM_REGISTRY" != "undefined" && "$ORIGINAL_NPM_REGISTRY" != "$SELECTED_NPM_REGISTRY" ]]; then
        npm config set registry "$ORIGINAL_NPM_REGISTRY" 2>/dev/null || true
    else
        npm config set registry https://registry.npmjs.org 2>/dev/null || true
    fi
    echo -e "${CYAN}[信息]${NC} 已恢复 npm 源设置"
}

# ============================================================
# 刷新 PATH（核心：避免重启终端）
# ============================================================
refresh_path() {
    # Homebrew 路径 (Apple Silicon vs Intel)
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    # npm 全局路径
    if [[ -d "$HOME/.npm-global/bin" ]]; then
        export PATH="$HOME/.npm-global/bin:$PATH"
    fi

    # Node.js 路径（Homebrew 安装）
    if [[ -d "/opt/homebrew/opt/node/bin" ]]; then
        export PATH="/opt/homebrew/opt/node/bin:$PATH"
    elif [[ -d "/usr/local/opt/node/bin" ]]; then
        export PATH="/usr/local/opt/node/bin:$PATH"
    fi
}

# 检查命令是否存在
command_exists() {
    refresh_path
    command -v "$1" &> /dev/null
}

# ============================================================
# GitHub 镜像源测速与选择（并发测试）
# ============================================================

# 测试单个镜像源并记录响应时间
# 参数: test_url mirror_url output_file name
# 输出: 将结果写入 output_file
test_mirror_with_timing() {
    local test_url="$1"
    local mirror_url="$2"
    local output_file="$3"
    local name="$4"

    local start_time=$(date +%s%3N 2>/dev/null || date +%s)

    # 使用 curl 测试 HTTP 请求（HEAD 请求，超时 8 秒）
    if curl -sfI --connect-timeout 5 --max-time 8 "$test_url" &> /dev/null; then
        local end_time=$(date +%s%3N 2>/dev/null || date +%s)
        local elapsed=$((end_time - start_time))
        echo "${elapsed}|${mirror_url}|${name}" > "$output_file"
    else
        echo "failed|${mirror_url}|${name}" > "$output_file"
    fi
}

# 并发选择最快的可用 GitHub 镜像源
# 返回: 最佳镜像 URL，如果没有可用镜像返回空字符串
select_best_mirror() {
    print_step "并发测试 GitHub 镜像源..." >&2

    # 镜像列表（简化版）：只保留自建 Cloudflare 代理
    local mirror_configs=(
        # 自建 Cloudflare Worker 代理（自定义域名，优先）
        "https://openclaw.mintmind.io/https://github.com/|https://openclaw.mintmind.io/https://github.com/npm/cli/raw/latest/README.md|openclaw-proxy"
        # 自建 Cloudflare Worker 代理（workers.dev 备用）
        "https://openclaw-gh-proxy.dejuanrohan1.workers.dev/https://github.com/|https://openclaw-gh-proxy.dejuanrohan1.workers.dev/https://github.com/npm/cli/raw/latest/README.md|openclaw-proxy-workers"
    )

    # 创建临时目录存放测试结果
    local tmp_dir=$(mktemp -d)
    local pids=()

    # 并发启动所有测试
    echo "  正在并发测试 ${#mirror_configs[@]} 个镜像源..." >&2
    for i in "${!mirror_configs[@]}"; do
        local config="${mirror_configs[$i]}"
        local mirror_url=$(echo "$config" | cut -d'|' -f1)
        local test_url=$(echo "$config" | cut -d'|' -f2)
        local name=$(echo "$config" | cut -d'|' -f3)
        test_mirror_with_timing "$test_url" "$mirror_url" "$tmp_dir/result_$i" "$name" &
        pids+=($!)
    done

    # 等待所有测试完成（最多等待 12 秒）
    local wait_count=0
    while [[ $wait_count -lt 24 ]]; do
        local all_done=true
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_done=false
                break
            fi
        done
        if $all_done; then
            break
        fi
        sleep 0.5
        ((wait_count++))
    done

    # 收集结果并排序
    local results=()
    for i in "${!mirror_configs[@]}"; do
        local result_file="$tmp_dir/result_$i"
        if [[ -f "$result_file" ]]; then
            local content=$(cat "$result_file")
            local timing=$(echo "$content" | cut -d'|' -f1)
            local url=$(echo "$content" | cut -d'|' -f2)
            local name=$(echo "$content" | cut -d'|' -f3)
            
            if [[ "$timing" != "failed" ]]; then
                echo -e "  ${name}: ${GREEN}${timing}ms${NC}" >&2
                results+=("$timing|$url|$name")
            else
                echo -e "  ${name}: ${RED}不可用${NC}" >&2
            fi
        fi
    done

    # 清理临时文件
    rm -rf "$tmp_dir"

    # 按响应时间排序，选择最快的
    if [[ ${#results[@]} -gt 0 ]]; then
        # 使用 sort 按数字排序
        local best=$(printf '%s\n' "${results[@]}" | sort -t'|' -k1 -n | head -1)
        local best_url=$(echo "$best" | cut -d'|' -f2)
        local best_name=$(echo "$best" | cut -d'|' -f3)
        local best_time=$(echo "$best" | cut -d'|' -f1)
        
        print_success "已选择最快镜像源: $best_name (${best_time}ms)" >&2
        echo "$best_url"
    else
        print_warning "所有镜像源均不可用，将直接连接 GitHub" >&2
        echo ""
    fi
}

# 应用镜像配置（简化版）
apply_git_mirror() {
    local mirror_url="$1"

    if [[ -z "$mirror_url" ]]; then
        return
    fi

    # 辅助函数：配置单个镜像的所有 URL 重定向
    set_mirror_config() {
        local prefix="$1"
        git config --global --unset-all url."$prefix".insteadOf 2>/dev/null || true
        git config --global --add url."$prefix".insteadOf "https://github.com/"
        git config --global --add url."$prefix".insteadOf "ssh://git@github.com/"
        git config --global --add url."$prefix".insteadOf "git@github.com:"
    }

    # 配置自建代理镜像
    case "$mirror_url" in
        *mintmind.io*)
            set_mirror_config "https://openclaw.mintmind.io/https://github.com/"
            ;;
        *workers.dev*)
            set_mirror_config "https://openclaw-gh-proxy.dejuanrohan1.workers.dev/https://github.com/"
            ;;
        *)
            set_mirror_config "$mirror_url"
            ;;
    esac
}

# 清除镜像配置（简化版）
remove_git_mirror() {
    # 自建代理前缀
    local prefixes=(
        "https://openclaw.mintmind.io/https://github.com/"
        "https://openclaw-gh-proxy.dejuanrohan1.workers.dev/https://github.com/"
    )

    for prefix in "${prefixes[@]}"; do
        git config --global --unset url."$prefix".insteadOf 2>/dev/null || true
    done
}

# ============================================================
# 开始安装
# ============================================================
echo -e "${MAGENTA}"
cat << 'EOF'

  ╔═══════════════════════════════════════════════════════╗
  ║         OpenClaw 一键安装脚本 (macOS)                 ║
  ║                                                       ║
  ║  将自动安装: Git, Node.js (LTS), OpenClaw             ║
  ╚═══════════════════════════════════════════════════════╝

EOF
echo -e "${NC}"

# ============================================================
# 步骤 0: 检查/安装 Homebrew
# ============================================================
print_step "检查 Homebrew 包管理器..."

if command_exists brew; then
    print_success "Homebrew 已安装"
else
    print_warning "Homebrew 未安装，正在安装..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # 立即激活 Homebrew
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if command_exists brew; then
        print_success "Homebrew 安装完成"
    else
        print_error "Homebrew 安装失败，请手动安装: https://brew.sh"
        exit 1
    fi
fi

# ============================================================
# 步骤 1: 安装 Git
# ============================================================
print_step "检查 Git..."

if command_exists git; then
    git_version=$(git --version)
    print_success "Git 已安装: $git_version"
else
    echo "正在安装 Git..."
    brew install git < /dev/null

    refresh_path

    if command_exists git; then
        print_success "Git 安装完成"
    else
        print_error "Git 安装失败"
        exit 1
    fi
fi

# ============================================================
# 步骤 2: 安装 Node.js (LTS)
# ============================================================
print_step "检查 Node.js..."

need_install_node=true

if command_exists node; then
    node_version=$(node --version)
    major_version=$(echo "$node_version" | sed 's/v\([0-9]*\).*/\1/')

    if [[ "$major_version" -ge 18 ]]; then
        print_success "Node.js 已安装: $node_version (满足 LTS 最低要求)"
        need_install_node=false
    else
        print_warning "当前 Node.js 版本 $node_version 过低，将升级到 LTS 版本..."
    fi
fi

if $need_install_node; then
    echo "正在安装 Node.js LTS..."
    brew install node < /dev/null

    refresh_path

    if command_exists node; then
        node_version=$(node --version)
        print_success "Node.js 安装完成: $node_version"
    else
        print_error "Node.js 安装失败，请手动安装: https://nodejs.org/"
        exit 1
    fi
fi

# ============================================================
# 注：GitHub 镜像配置已移至回退机制，核心安装不再需要 GitHub
# ============================================================

# ============================================================
# 步骤 3.5: 选择最佳 NPM 镜像源
# ============================================================
select_best_npm_registry

# ============================================================
# 步骤 4: 安装 OpenClaw
# ============================================================
print_step "检查 OpenClaw..."

# Cloudflare R2 托管的包 URL（避免 GitHub 访问问题）
OPENCLAW_R2_URL="https://packages.mintmind.io/openclaw-2026.1.30.tgz"

if command_exists openclaw; then
    print_success "OpenClaw 已安装"
else
    echo "正在安装 OpenClaw（从 Cloudflare 下载）..."

    # 使用 --ignore-scripts 避免 postinstall 脚本失败导致安装不完整
    # （如 node-llama-cpp 在某些平台编译失败）
    if npm install -g "$OPENCLAW_R2_URL" --ignore-scripts --progress --loglevel=notice; then
        echo ""
    else
        print_warning "从 Cloudflare 下载失败，尝试 npm registry..."
        npm install -g openclaw --ignore-scripts --progress --loglevel=notice
    fi

    refresh_path

    if command_exists openclaw; then
        print_success "OpenClaw 安装完成"
    else
        print_error "OpenClaw 安装失败"
        echo ""
        echo "如果仍然失败，请尝试以下方法："
        echo "1. 使用 VPN 或代理"
        echo "2. 手动配置 Git 代理："
        echo "   git config --global http.proxy http://127.0.0.1:7890"
        echo "   git config --global https.proxy http://127.0.0.1:7890"
        echo "3. 然后重新运行: npm install -g openclaw --ignore-scripts"
        exit 1
    fi
fi



# ============================================================
# 步骤 5: 安装飞书插件
# ============================================================
print_step "安装飞书插件..."

# Cloudflare R2 托管的飞书插件 URL
FEISHU_R2_URL="https://packages.mintmind.io/feishu-0.1.6.tgz"
FEISHU_TMP="/tmp/feishu-plugin.tgz"

# 优先从 R2 下载安装，如果失败则从 npm 安装
if curl -sL -o "$FEISHU_TMP" "$FEISHU_R2_URL" && [[ -f "$FEISHU_TMP" ]]; then
    openclaw plugins install "$FEISHU_TMP" < /dev/null
    rm -f "$FEISHU_TMP"
else
    print_warning "从 Cloudflare 下载失败，尝试 npm registry..."
    openclaw plugins install @m1heng-clawd/feishu < /dev/null
fi

print_success "飞书插件安装完成"


# ============================================================
# 完成
# ============================================================
echo -e "${GREEN}"
cat << 'EOF'

  ╔═══════════════════════════════════════════════════════╗
  ║                     安装完成!                         ║
  ╠═══════════════════════════════════════════════════════╣
  ║                                                       ║
  ║  已安装:                                              ║
  ║    - Git                                              ║
  ║    - Node.js                                          ║
  ║    - OpenClaw                                         ║
  ║    - 飞书插件                                         ║
  ║                                                       ║
  ║  现在可以使用 openclaw 命令了!                        ║
  ║                                                       ║
  ╚═══════════════════════════════════════════════════════╝

EOF
echo -e "${NC}"

# 显示版本信息
echo -e "${CYAN}已安装版本:${NC}"
echo "  Git:      $(git --version)"
echo "  Node.js:  $(node --version)"
echo "  OpenClaw: $(openclaw --version 2>/dev/null || echo '已安装')"

# ============================================================
# 安装文件处理技能
# ============================================================
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
echo ""

# 默认安装文件处理技能（可通过 SKIP_SKILLS=1 跳过）
if [[ "${SKIP_SKILLS:-}" != "1" ]]; then
    print_step "安装文件处理技能..."

    # 检查并安装 Python 3.12
    print_step "检查 Python..."

    python_cmd=""
    need_install_python=true

    # 检查 python3.12
    if command_exists python3.12; then
        python_version=$(python3.12 --version 2>&1)
        print_success "Python 3.12 已安装: $python_version"
        python_cmd="python3.12"
        need_install_python=false
    # 检查 python3 版本是否 >= 3.12
    elif command_exists python3; then
        python_version=$(python3 --version 2>&1)
        major_minor=$(echo "$python_version" | sed 's/Python \([0-9]*\.[0-9]*\).*/\1/')
        if [[ $(echo "$major_minor >= 3.12" | bc -l 2>/dev/null || echo "0") == "1" ]] || [[ "$major_minor" == "3.12" ]] || [[ "$major_minor" > "3.12" ]]; then
            print_success "Python 已安装: $python_version"
            python_cmd="python3"
            need_install_python=false
        else
            print_warning "当前 Python 版本 $python_version 过低，将安装 Python 3.12..."
        fi
    fi

    if $need_install_python; then
        echo "正在安装 Python 3.12..."
        brew install python@3.12 < /dev/null

        refresh_path

        # 添加 Python 3.12 到 PATH
        if [[ -d "/opt/homebrew/opt/python@3.12/bin" ]]; then
            export PATH="/opt/homebrew/opt/python@3.12/bin:$PATH"
        elif [[ -d "/usr/local/opt/python@3.12/bin" ]]; then
            export PATH="/usr/local/opt/python@3.12/bin:$PATH"
        fi

        if command_exists python3.12; then
            python_version=$(python3.12 --version 2>&1)
            print_success "Python 3.12 安装完成: $python_version"
            python_cmd="python3.12"
        else
            print_error "Python 3.12 安装失败"
            exit 1
        fi
    fi

    # 安装文件处理技能
    print_step "安装 PDF, PPT, Excel, Docx 技能..."

    # 从 Cloudflare R2 下载 skills 包
    SKILLS_R2_URL="https://packages.mintmind.io/anthropics-skills.tar.gz"
    SKILLS_TMP="/tmp/anthropics-skills.tar.gz"
    SKILLS_DIR="/tmp/anthropics-skills"

    # 下载并解压
    if curl -sL -o "$SKILLS_TMP" "$SKILLS_R2_URL" && [[ -f "$SKILLS_TMP" ]]; then
        rm -rf "$SKILLS_DIR"
        mkdir -p "$SKILLS_DIR"
        tar -xzf "$SKILLS_TMP" -C "$SKILLS_DIR" --strip-components=1
        
        # 从本地目录安装技能
        npx -y skills add "$SKILLS_DIR" --skill xlsx --skill pdf --skill pptx --skill docx --agent openclaw -y -g < /dev/null
        
        # 清理临时文件
        rm -rf "$SKILLS_TMP" "$SKILLS_DIR"
    else
        print_warning "从 Cloudflare 下载失败，尝试 GitHub..."
        # 临时配置 Git 镜像
        SKILLS_MIRROR=$(select_best_mirror)
        apply_git_mirror "$SKILLS_MIRROR"
        npx -y skills add anthropics/skills --skill xlsx --skill pdf --skill pptx --skill docx --agent openclaw -y -g < /dev/null
        remove_git_mirror
    fi

    print_success "文件处理技能安装完成"

    echo ""
    echo -e "${CYAN}已安装技能:${NC}"
    echo "  - xlsx (Excel 文件处理)"
    echo "  - pdf (PDF 文件处理)"
    echo "  - pptx (PowerPoint 文件处理)"
    echo "  - docx (Word 文件处理)"
fi

# ============================================================
# 自动初始化 OpenClaw
# ============================================================
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
echo ""

print_step "初始化 OpenClaw..."
openclaw onboard --non-interactive --accept-risk --skip-daemon 2>&1 | grep -v "^$" || true

print_step "安装网关服务..."
if openclaw gateway install 2>&1; then
    print_success "网关服务安装完成"
else
    print_error "网关服务安装失败"
    exit 1
fi

print_step "启动网关服务..."
if openclaw gateway start 2>&1; then
    # 等待服务启动
    sleep 3
    print_success "网关服务启动完成"
else
    print_error "网关服务启动失败"
    exit 1
fi

print_success "OpenClaw 初始化完成"

# ============================================================
# 配置飞书 Channel
# ============================================================
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}配置飞书机器人${NC}"
echo ""
echo "请输入飞书应用的 App ID 和 App Secret"
echo "（可在飞书开放平台 https://open.feishu.cn 获取）"
echo ""

# 读取飞书 App ID
if [[ -t 0 ]]; then
    read -p "飞书 App ID: " feishu_app_id
elif [[ -e /dev/tty ]]; then
    read -p "飞书 App ID: " feishu_app_id < /dev/tty
fi

# 读取飞书 App Secret
if [[ -t 0 ]]; then
    read -p "飞书 App Secret: " feishu_app_secret
elif [[ -e /dev/tty ]]; then
    read -p "飞书 App Secret: " feishu_app_secret < /dev/tty
fi

if [[ -n "$feishu_app_id" && -n "$feishu_app_secret" ]]; then
    print_step "配置飞书..."
    openclaw channels add --channel feishu < /dev/null
    openclaw config set channels.feishu.appId "$feishu_app_id" < /dev/null
    openclaw config set channels.feishu.appSecret "$feishu_app_secret" < /dev/null
    print_success "飞书配置完成"
else
    print_warning "跳过飞书配置（未输入完整信息）"
fi

# ============================================================
# 配置 Qwen AI 模型
# ============================================================
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${YELLOW}配置 AI 模型 (Qwen)${NC}"
echo ""
echo "即将打开浏览器进行 Qwen 授权..."
echo "请在浏览器中完成登录授权"
echo ""

print_step "启动 Qwen 认证..."

# 首先启用 qwen-portal-auth plugin
openclaw plugins enable qwen-portal-auth 2>&1 | grep -v "^$" || true

# 然后进行认证（需要从 /dev/tty 读取交互式输入）
openclaw models auth login --provider qwen-portal --set-default < /dev/tty

# 复制 auth 配置到主 agent 目录
if [[ -f ~/.openclaw/agents/main/agent/auth-profiles.json ]]; then
    cp ~/.openclaw/agents/main/agent/auth-profiles.json ~/.openclaw/agents/main/auth-profiles.json
fi

# 重启 gateway 使配置生效
print_step "重启网关服务..."
openclaw gateway restart 2>&1 | grep -v "^$" || true

print_success "Qwen 认证完成"

# ============================================================
# 恢复 npm 源设置
# ============================================================
restore_npm_registry

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${GREEN}"
cat << 'EOF'
  ╔═══════════════════════════════════════════════════════╗
  ║                     配置完成!                         ║
  ╠═══════════════════════════════════════════════════════╣
  ║                                                       ║
  ║  OpenClaw 已准备就绪!                                 ║
  ║                                                       ║
  ║  常用命令:                                            ║
  ║    openclaw status    - 查看状态                      ║
  ║    openclaw dashboard - 打开控制面板                  ║
  ║    openclaw doctor    - 健康检查                      ║
  ║                                                       ║
  ╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
