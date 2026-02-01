#!/bin/bash
#
# OpenClaw 彻底卸载脚本 (macOS / Linux)
# 用于测试：完全删除所有 OpenClaw 相关文件
#

# ============================================================
# 颜色定义
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step() { echo -e "${CYAN}[清理]${NC} $1"; }
print_done() { echo -e "${GREEN}[完成]${NC} $1"; }

# ============================================================
# 检测操作系统
# ============================================================
OS="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
fi

echo -e "${YELLOW}========== OpenClaw 彻底卸载 ==========${NC}"
echo ""

# ============================================================
# 1. 停止并清理服务
# ============================================================
print_step "停止服务..."

# 尝试使用 CLI 停止
if command -v openclaw &> /dev/null; then
    openclaw gateway stop 2>/dev/null || true
    openclaw gateway uninstall 2>/dev/null || true
fi

if [[ "$OS" == "macos" ]]; then
    # macOS: launchd
    launchctl bootout gui/$UID/bot.molt.gateway 2>/dev/null || true
    rm -f ~/Library/LaunchAgents/bot.molt.gateway.plist 2>/dev/null || true
elif [[ "$OS" == "linux" ]]; then
    # Linux: systemd
    systemctl --user disable --now openclaw-gateway.service 2>/dev/null || true
    rm -f ~/.config/systemd/user/openclaw-gateway.service 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
fi

print_done "服务已清理"

# ============================================================
# 2. 卸载 CLI
# ============================================================
print_step "卸载 CLI..."

# pnpm
pnpm remove -g openclaw 2>/dev/null || true

# npm
npm rm -g openclaw 2>/dev/null || true

# bun
bun remove -g openclaw 2>/dev/null || true

print_done "CLI 已卸载"

# ============================================================
# 3. 删除所有相关目录和文件
# ============================================================
print_step "删除文件..."

# OpenClaw 主目录
rm -rf ~/.openclaw 2>/dev/null || true
rm -rf "${OPENCLAW_STATE_DIR}" 2>/dev/null || true

# macOS 应用
rm -rf /Applications/OpenClaw.app 2>/dev/null || true

# Claude Code 中的 OpenClaw 相关技能
rm -rf ~/.claude/skills/*openclaw* 2>/dev/null || true

# 通过 skills 命令安装的技能 (pdf, xlsx, pptx, docx)
rm -rf ~/.claude/skills/anthropics 2>/dev/null || true

# 可能的缓存目录
rm -rf ~/.cache/openclaw 2>/dev/null || true
rm -rf ~/Library/Caches/openclaw 2>/dev/null || true

# npm/pnpm 全局安装残留
rm -rf ~/.npm/_npx/*openclaw* 2>/dev/null || true
rm -rf ~/.pnpm-store/*openclaw* 2>/dev/null || true

print_done "文件已删除"

# ============================================================
# 4. 清理 shell 配置中的相关内容（可选，不自动执行）
# ============================================================
# 注意：不自动修改 shell 配置文件，避免意外

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${GREEN}========== 卸载完成 ==========${NC}"
echo ""

# 验证
if command -v openclaw &> /dev/null; then
    echo -e "${RED}警告: openclaw 命令仍然存在${NC}"
else
    echo -e "${GREEN}openclaw 命令已移除${NC}"
fi

if [[ -d ~/.openclaw ]]; then
    echo -e "${RED}警告: ~/.openclaw 目录仍然存在${NC}"
else
    echo -e "${GREEN}~/.openclaw 目录已删除${NC}"
fi

# ============================================================
# 5. 重启终端
# ============================================================
echo ""
print_step "重启终端..."
sleep 1
exec $SHELL -l
