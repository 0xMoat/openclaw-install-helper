#!/bin/bash
#
# OpenClaw 一键安装脚本 (macOS)
# 自动安装 Git, Node.js (LTS), pnpm, OpenClaw 及飞书插件
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

    # pnpm 路径
    export PNPM_HOME="$HOME/Library/pnpm"
    if [[ -d "$PNPM_HOME" ]]; then
        export PATH="$PNPM_HOME:$PATH"
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
# 开始安装
# ============================================================
echo -e "${MAGENTA}"
cat << 'EOF'

  ╔═══════════════════════════════════════════════════════╗
  ║          OpenClaw 一键安装脚本 (macOS)                ║
  ║                                                       ║
  ║  将自动安装: Git, Node.js (LTS), pnpm, OpenClaw        ║
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
    brew install git

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
    brew install node

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
# 步骤 3: 安装 pnpm
# ============================================================
print_step "检查 pnpm..."

if command_exists pnpm; then
    pnpm_version=$(pnpm --version)
    print_success "pnpm 已安装: v$pnpm_version"
else
    echo "正在安装 pnpm..."

    # 使用官方推荐的安装方式
    curl -fsSL https://get.pnpm.io/install.sh | sh -

    # 立即设置 pnpm 环境变量
    export PNPM_HOME="$HOME/Library/pnpm"
    export PATH="$PNPM_HOME:$PATH"

    refresh_path

    if command_exists pnpm; then
        pnpm_version=$(pnpm --version)
        print_success "pnpm 安装完成: v$pnpm_version"
    else
        print_error "pnpm 安装失败"
        echo "请尝试手动安装: npm install -g pnpm"
        exit 1
    fi
fi

# ============================================================
# 步骤 4: 安装 OpenClaw
# ============================================================
print_step "检查 OpenClaw..."

if command_exists openclaw; then
    print_success "OpenClaw 已安装"
else
    echo "正在安装 OpenClaw..."
    pnpm add -g openclaw

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

openclaw plugins install @m1heng-clawd/feishu

print_success "飞书插件安装完成"

# ============================================================
# 配置 Shell（确保下次打开终端时 PATH 正确）
# ============================================================
print_step "配置 Shell 环境..."

# 检测当前 shell
current_shell=$(basename "$SHELL")
shell_config=""

if [[ "$current_shell" == "zsh" ]]; then
    shell_config="$HOME/.zshrc"
elif [[ "$current_shell" == "bash" ]]; then
    if [[ -f "$HOME/.bash_profile" ]]; then
        shell_config="$HOME/.bash_profile"
    else
        shell_config="$HOME/.bashrc"
    fi
fi

if [[ -n "$shell_config" ]]; then
    # 添加 pnpm 配置（如果不存在）
    if ! grep -q "PNPM_HOME" "$shell_config" 2>/dev/null; then
        echo '' >> "$shell_config"
        echo '# pnpm' >> "$shell_config"
        echo 'export PNPM_HOME="$HOME/Library/pnpm"' >> "$shell_config"
        echo 'export PATH="$PNPM_HOME:$PATH"' >> "$shell_config"
        print_success "已将 pnpm 配置添加到 $shell_config"
    fi
fi

# ============================================================
# 完成
# ============================================================
echo -e "${GREEN}"
cat << 'EOF'

  ╔═══════════════════════════════════════════════════════╗
  ║                    安装完成!                          ║
  ╠═══════════════════════════════════════════════════════╣
  ║                                                       ║
  ║  已安装:                                              ║
  ║    - Git                                              ║
  ║    - Node.js                                          ║
  ║    - pnpm                                             ║
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
echo "  pnpm:     v$(pnpm --version)"
echo "  OpenClaw: $(openclaw --version 2>/dev/null || echo '已安装')"
