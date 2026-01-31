# OpenClaw 一键安装脚本

面向非技术用户的一键安装工具，自动安装 OpenClaw 及其所有依赖。

## 使用方法

### macOS 用户

打开「终端」，复制粘贴以下命令后按回车：

```bash
curl -fsSL https://raw.githubusercontent.com/0xmoat/openclaw-install-helper/main/install.sh | bash
```

### Windows 用户

以**管理员身份**打开「PowerShell」，复制粘贴以下命令后按回车：

```powershell
irm https://raw.githubusercontent.com/0xmoat/openclaw-install-helper/main/install.ps1 | iex
```

> **注意**：如果提示执行策略错误，请先运行：
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

## 安装内容

脚本会自动检测并安装以下组件：

| 组件 | 说明 | 依赖 |
|------|------|------|
| Git | 版本控制工具 | 无 |
| Node.js (LTS) | JavaScript 运行时 | 无 |
| pnpm | 包管理器 | Node.js |
| OpenClaw | 主程序 | pnpm |
| 飞书插件 | @m1heng-clawd/feishu | OpenClaw |

## 依赖关系

```
Git (独立安装)
     │
Node.js LTS (独立安装)
     │
     ▼
   pnpm (需要 Node.js)
     │
     ▼
  OpenClaw (需要 pnpm)
     │
     ▼
  飞书插件 (需要 OpenClaw)
```

## 本地测试

如需本地测试脚本：

**macOS:**
```bash
./install.sh
```

**Windows (PowerShell):**
```powershell
.\install.ps1
```

## 特点

- **无需重启终端**：脚本会自动刷新 PATH 环境变量
- **智能检测**：已安装的组件会跳过，避免重复安装
- **版本检查**：自动检查 Node.js 版本是否满足要求（≥18）
- **自动安装依赖**：
  - macOS：自动安装 Homebrew（如果不存在）
  - Windows：支持 winget 和直接下载两种方式

## 系统要求

| 系统 | 最低版本 | 包管理器 |
|------|----------|----------|
| Windows | Windows 10 | winget（可选，脚本会自动处理） |
| macOS | macOS 10.15+ | Homebrew（自动安装） |

## 常见问题

### Windows: 无法运行脚本

PowerShell 默认可能禁止执行脚本，请运行：
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Windows: 没有 winget 怎么办？

脚本会自动检测，如果没有 winget 会自动切换到直接下载安装模式。

### macOS: 需要安装 Xcode 命令行工具

如果提示需要安装 Xcode 命令行工具，请按提示点击「安装」。
