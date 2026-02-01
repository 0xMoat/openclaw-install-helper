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
# GitHub 镜像源测速与选择
# ============================================================

# 测试单个镜像源是否真正可用（通过实际 git 操作）
# 返回: "success" 或 "fail"
test_mirror_available() {
    local mirror_url="$1"

    # 使用 git ls-remote 测试镜像是否真正可用
    # 测试一个公开的小仓库
    local test_url="${mirror_url}anthropics/skills.git"

    if timeout 10 git ls-remote "$test_url" HEAD &> /dev/null; then
        echo "success"
    else
        echo "fail"
    fi
}

# 选择最快的可用 GitHub 镜像源
# 返回: 最佳镜像 URL，如果没有可用镜像返回空字符串
select_best_mirror() {
    print_step "测试 GitHub 镜像源可用性..." >&2

    local mirrors=(
        "https://ghfast.top/https://github.com/"
        "https://kkgithub.com/"
        "https://hub.gitmirror.com/"
        "https://mirror.ghproxy.com/https://github.com/"
        "https://gh.qninq.cn/https://github.com/"
        "https://gh.api.99988866.xyz/https://github.com/"
        "https://github.moeyy.xyz/https://github.com/"
        "https://gh-proxy.com/https://github.com/"
    )

    local mirror_names=(
        "ghfast.top"
        "kkgithub.com"
        "gitmirror.com"
        "ghproxy.com"
        "gh.qninq.cn"
        "gh.api.99988866.xyz"
        "github.moeyy.xyz"
        "gh-proxy.com"
    )

    local available_mirrors=()

    for i in "${!mirrors[@]}"; do
        local mirror="${mirrors[$i]}"
        local name="${mirror_names[$i]}"

        echo -n "  测试 $name ... " >&2

        local result
        result=$(test_mirror_available "$mirror")

        if [[ "$result" == "success" ]]; then
            echo -e "${GREEN}可用${NC}" >&2
            available_mirrors+=("$mirror")
        else
            echo -e "${RED}不可用${NC}" >&2
        fi
    done

    # 选择第一个可用的镜像（按优先级顺序）
    if [[ ${#available_mirrors[@]} -gt 0 ]]; then
        print_success "已选择可用镜像源" >&2
        echo "${available_mirrors[0]}"
    else
        print_warning "所有镜像源均不可用，将直接连接 GitHub" >&2
        echo ""
    fi
}

# 应用镜像配置
apply_git_mirror() {
    local mirror_url="$1"

    if [[ -z "$mirror_url" ]]; then
        return
    fi

    # 根据镜像 URL 直接配置对应的 insteadOf
    case "$mirror_url" in
        *ghfast.top*)
            git config --global url."https://ghfast.top/https://github.com/".insteadOf "https://github.com/"
            ;;
        *kkgithub.com*)
            git config --global url."https://kkgithub.com/".insteadOf "https://github.com/"
            ;;
        *gitmirror.com*)
            git config --global url."https://hub.gitmirror.com/".insteadOf "https://github.com/"
            ;;
        *ghproxy.com*)
            git config --global url."https://mirror.ghproxy.com/https://github.com/".insteadOf "https://github.com/"
            ;;
        *gh.qninq.cn*)
            git config --global url."https://gh.qninq.cn/https://github.com/".insteadOf "https://github.com/"
            ;;
        *gh.api.99988866.xyz*)
            git config --global url."https://gh.api.99988866.xyz/https://github.com/".insteadOf "https://github.com/"
            ;;
        *github.moeyy.xyz*)
            git config --global url."https://github.moeyy.xyz/https://github.com/".insteadOf "https://github.com/"
            ;;
        *gh-proxy.com*)
            git config --global url."https://gh-proxy.com/https://github.com/".insteadOf "https://github.com/"
            ;;
        *)
            git config --global url."$mirror_url".insteadOf "https://github.com/"
            ;;
    esac
}

# 清除镜像配置
remove_git_mirror() {
    # 清除所有可能的镜像配置
    git config --global --unset url."https://ghfast.top/https://github.com/".insteadOf 2>/dev/null || true
    git config --global --unset url."https://kkgithub.com/".insteadOf 2>/dev/null || true
    git config --global --unset url."https://hub.gitmirror.com/".insteadOf 2>/dev/null || true
    git config --global --unset url."https://mirror.ghproxy.com/https://github.com/".insteadOf 2>/dev/null || true
    git config --global --unset url."https://gh.qninq.cn/https://github.com/".insteadOf 2>/dev/null || true
    git config --global --unset url."https://gh.api.99988866.xyz/https://github.com/".insteadOf 2>/dev/null || true
    git config --global --unset url."https://github.moeyy.xyz/https://github.com/".insteadOf 2>/dev/null || true
    git config --global --unset url."https://gh-proxy.com/https://github.com/".insteadOf 2>/dev/null || true
    # 兼容旧配置
    git config --global --unset url."https://gh-proxy.com/https://github.com/".insteadOf 2>/dev/null || true
    git config --global --unset url."https://gitclone.com/github.com/".insteadOf 2>/dev/null || true
    git config --global --unset url."https://bgithub.xyz/".insteadOf 2>/dev/null || true
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
# 步骤 3: 配置 Git 镜像（解决 GitHub 访问问题）
# ============================================================
BEST_MIRROR=$(select_best_mirror)
apply_git_mirror "$BEST_MIRROR"
if [[ -n "$BEST_MIRROR" ]]; then
    print_success "Git 镜像配置完成"
fi

# ============================================================
# 步骤 4: 安装 OpenClaw
# ============================================================
print_step "检查 OpenClaw..."

if command_exists openclaw; then
    print_success "OpenClaw 已安装"
else
    echo "正在安装 OpenClaw..."
    echo "提示: 如果安装过程较慢，请耐心等待（首次安装可能需要 5-10 分钟）..."

    npm install -g openclaw < /dev/null

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
        echo "3. 然后重新运行: npm install -g openclaw"
        exit 1
    fi
fi

# ============================================================
# 清理：安装完成后移除 Git 镜像配置（可选）
# ============================================================
print_step "清理 Git 镜像配置..."
remove_git_mirror
print_success "Git 配置已恢复"

# ============================================================
# 步骤 5: 安装飞书插件
# ============================================================
print_step "安装飞书插件..."

openclaw plugins install @m1heng-clawd/feishu < /dev/null

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

    # 临时配置 Git 镜像以解决 GitHub 访问问题
    SKILLS_MIRROR=$(select_best_mirror)
    apply_git_mirror "$SKILLS_MIRROR"

    npx -y skills add anthropics/skills --skill xlsx --skill pdf --skill pptx --skill docx --agent openclaw -y -g < /dev/null

    # 恢复 Git 配置
    remove_git_mirror
    print_success "Git 配置已恢复"

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
