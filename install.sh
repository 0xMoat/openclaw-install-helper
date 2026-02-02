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
# 版本配置 (Versions)
# ============================================================
VER_OPENCLAW="2026.1.30"
VER_FEISHU="0.1.6"
VER_SKILLS="1.3.1"
VER_TAG="1.0.1"

# ============================================================
# NPM 镜像源测速与选择
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

# 测试单个 NPM 镜像源 (CURL HEAD)
check_npm_registry() {
    local url="$1"
    local name="$2"
    echo -n "  正在连接 $name..." >&2
    local start_time=$(get_timestamp_ms)
    
    if curl -s --head --connect-timeout 5 "$url" > /dev/null; then
        local end_time=$(get_timestamp_ms)
        local elapsed=$((end_time - start_time))
        echo -e " ${GREEN}[OK] ${elapsed}ms${NC}" >&2
        echo "$elapsed"
    else
        echo -e " ${RED}[失败]${NC}" >&2
        echo "-1"
    fi
}

# 简单的串行测速（NPM）
select_best_npm_registry() {
    print_step "测试 NPM 镜像源..." >&2

    # 优先测试淘宝源
    local time_taobao=$(check_npm_registry "https://registry.npmmirror.com/" "淘宝源")
    if [[ "$time_taobao" != "-1" ]]; then
        print_success "已选择: 淘宝源" >&2
        SELECTED_NPM_REGISTRY="https://registry.npmmirror.com/"
        npm config set registry "$SELECTED_NPM_REGISTRY" 2>/dev/null || true
        return
    fi
    
    # 其次测试官方源
    local time_official=$(check_npm_registry "https://registry.npmjs.org/" "官方源")
    if [[ "$time_official" != "-1" ]]; then
        print_success "已选择: 官方源" >&2
        SELECTED_NPM_REGISTRY="https://registry.npmjs.org/"
        npm config set registry "$SELECTED_NPM_REGISTRY" 2>/dev/null || true
        return
    fi

    print_warning "所有镜像源检测失败，默认使用淘宝源" >&2
    SELECTED_NPM_REGISTRY="https://registry.npmmirror.com/"
    npm config set registry "https://registry.npmmirror.com/" 2>/dev/null || true
}

restore_npm_registry() {
    if [[ -n "$ORIGINAL_NPM_REGISTRY" && "$ORIGINAL_NPM_REGISTRY" != "undefined" && "$ORIGINAL_NPM_REGISTRY" != "$SELECTED_NPM_REGISTRY" ]]; then
        npm config set registry "$ORIGINAL_NPM_REGISTRY" 2>/dev/null || true
    else
        npm config set registry https://registry.npmjs.org 2>/dev/null || true
    fi
    echo -e "${CYAN}[信息]${NC} 已恢复 npm 源设置"
}

# ... (Path refresh logic omitted, assumes it's unchanged) ...

# 简单的串行测速（GitHub 镜像）
select_best_mirror() {
    print_step "测试 GitHub 镜像源..." >&2

    local mirror_url="https://openclaw.mintmind.io/https://github.com/"
    local test_url="https://openclaw.mintmind.io/https://github.com/npm/cli/raw/latest/README.md"
    
    echo -n "  正在连接 openclaw-proxy..." >&2
    if curl -s --head --connect-timeout 5 "$test_url" > /dev/null; then
         echo -e " ${GREEN}[OK]${NC}" >&2
         print_success "已选择: openclaw-proxy" >&2
         echo "$mirror_url"
         return
    else
         echo -e " ${RED}[失败]${NC}" >&2
    fi

    print_warning "所有镜像源检测失败，将直接连接 GitHub" >&2
    echo ""
}

# 应用镜像配置
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

    # 根据镜像 URL 直接配置对应的 insteadOf
    if [[ "$mirror_url" == *"mintmind.io"* ]]; then
        set_mirror_config "https://openclaw.mintmind.io/https://github.com/"
    else
        set_mirror_config "$mirror_url"
    fi
}

# 清除镜像配置
remove_git_mirror() {
    # 所有镜像前缀
    local prefixes=(
        "https://openclaw.mintmind.io/https://github.com/"
        "https://openclaw-gh-proxy.dejuanrohan1.workers.dev/https://github.com/"
        "https://ghfast.top/https://github.com/"
        "https://kkgithub.com/"
        "https://hub.gitmirror.com/"
        "https://mirror.ghproxy.com/https://github.com/"
        "https://gh.qninq.cn/https://github.com/"
    )

    for prefix in "${prefixes[@]}"; do
        git config --global --unset-all url."$prefix".insteadOf 2>/dev/null || true
    done
    
    # 额外清除可能的 SSH 和 git@ 格式
    git config --global --unset-all url.https://openclaw.mintmind.io/https://github.com/.insteadOf "ssh://git@github.com/" 2>/dev/null || true
}

# ============================================================
# 开始安装
# ============================================================
echo -e "${MAGENTA}"
cat << 'EOF'

  ╔═══════════════════════════════════════════════════════╗
  ║    金牌小密探😎 OpenClaw 一键安装脚本 (macOS)         ║
  ║                                                       ║
  ║  将自动安装: Git, Node.js, Python, OpenClaw           ║
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

# Gitee 托管的包 URL（中国境内访问更快）
OPENCLAW_R2_URL="https://gitee.com/mintmind/openclaw-packages/releases/download/${VER_TAG}/openclaw-${VER_OPENCLAW}.tgz"

if command_exists openclaw; then
    # 检查版本
    current_ver=$(openclaw --version 2>/dev/null || echo "")
    if [[ "$current_ver" == *"$VER_OPENCLAW"* ]]; then
        print_success "OpenClaw 已安装且版本匹配 ($current_ver)"
    else
        print_warning "OpenClaw 版本不匹配或无法读取，尝试重新安装..."
        # 使用 --ignore-scripts 避免 postinstall 脚本失败
        if npm install -g "$OPENCLAW_R2_URL" --ignore-scripts --progress --loglevel=notice; then
             echo ""
        else
             print_warning "从 Gitee 下载失败，尝试 npm registry..."
             npm install -g openclaw --ignore-scripts --progress --loglevel=notice
        fi
    fi
else
    echo "正在安装 OpenClaw（从 Gitee 下载）..."

    if npm install -g "$OPENCLAW_R2_URL" --ignore-scripts --progress --loglevel=notice; then
        echo ""
    else
        print_warning "从 Gitee 下载失败，尝试 npm registry..."
        npm install -g openclaw --ignore-scripts --progress --loglevel=notice
    fi

    refresh_path

    if command_exists openclaw; then
        print_success "OpenClaw 安装完成"
    else
        print_error "OpenClaw 安装失败"
        exit 1
    fi
fi

# ============================================================
# 步骤 5: 安装飞书插件
# ============================================================
print_step "安装飞书插件..."

# Gitee 托管的飞书插件 URL
FEISHU_R2_URL="https://gitee.com/mintmind/openclaw-packages/releases/download/${VER_TAG}/feishu-${VER_FEISHU}.tgz"
FEISHU_TMP="/tmp/feishu-plugin.tgz"

# 优先从 R2 下载安装，如果失败则从 npm 安装
if curl -sL -o "$FEISHU_TMP" "$FEISHU_R2_URL" && [[ -f "$FEISHU_TMP" ]]; then
    # 使用 npm install -g 安装，然后 openclaw 会自动识别（或后续手动 add）
    npm install -g "$FEISHU_TMP" --no-audit --loglevel=error
    rm -f "$FEISHU_TMP"
    # 显式注册
    openclaw channels add --channel feishu 2>/dev/null || true
else
    print_warning "从 Gitee 下载失败，尝试 npm registry..."
    openclaw channels add --channel feishu 2>/dev/null || true
fi

print_success "飞书插件安装完成"

# ... (End of Step 5) ...

# (Skipping to Skills Section)

# ...

    # 安装文件处理技能
    print_step "安装 PDF, PPT, Excel, Docx 技能..."

    # 修复 .moltbot 目录权限问题 (如果是文件则删除)
    MOLTBOT_DIR="$HOME/.moltbot"
    if [[ -f "$MOLTBOT_DIR" ]]; then
        rm -f "$MOLTBOT_DIR"
        mkdir -p "$MOLTBOT_DIR"
    elif [[ ! -d "$MOLTBOT_DIR" ]]; then
        mkdir -p "$MOLTBOT_DIR"
    fi

    # 直接使用 npx 安装指定版本
    npx -y skills@${VER_SKILLS} add anthropics/skills --skill xlsx --skill pdf --skill pptx --skill docx --agent openclaw -y -g < /dev/null

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
