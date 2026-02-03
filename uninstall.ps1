#Requires -Version 5.1
<#
.SYNOPSIS
    OpenClaw 彻底卸载脚本 (Windows)
.DESCRIPTION
    用于测试：完全删除所有 OpenClaw 相关文件
#>

# ============================================================
# 辅助函数
# ============================================================
function Write-Step { param($Message) Write-Host "[清理] $Message" -ForegroundColor Cyan }
function Write-Done { param($Message) Write-Host "[完成] $Message" -ForegroundColor Green }

Write-Host "========== OpenClaw 彻底卸载 ==========" -ForegroundColor Yellow
Write-Host ""

# ============================================================
# 1. 停止并清理服务
# ============================================================
Write-Step "停止服务..."

# 尝试使用 CLI 停止
try {
    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        openclaw gateway stop 2>$null
        openclaw gateway uninstall 2>$null
    }
} catch {}

# 删除计划任务
try {
    Unregister-ScheduledTask -TaskName "OpenClaw Gateway" -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

try {
    schtasks /Delete /F /TN "OpenClaw Gateway" 2>$null
} catch {}

Write-Done "服务已清理"

# ============================================================
# 2. 卸载 CLI
# ============================================================
Write-Step "卸载 CLI..."

# pnpm
try { pnpm remove -g openclaw 2>$null } catch {}

# npm
try { npm rm -g openclaw 2>$null } catch {}

# bun
try { bun remove -g openclaw 2>$null } catch {}

# 手动删除 npm 全局目录下的 openclaw 相关文件（确保彻底清理）
$npmGlobalDir = "$env:APPDATA\npm"
if (Test-Path $npmGlobalDir) {
    # 删除模块目录
    $openclaModuleDir = "$npmGlobalDir\node_modules\openclaw"
    if (Test-Path $openclaModuleDir) {
        Remove-Item -Recurse -Force $openclaModuleDir -ErrorAction SilentlyContinue
        Write-Host "  已删除: $openclaModuleDir" -ForegroundColor Gray
    }
    
    # 删除 shim 文件
    @("openclaw", "openclaw.cmd", "openclaw.ps1") | ForEach-Object {
        $shimPath = "$npmGlobalDir\$_"
        if (Test-Path $shimPath) {
            Remove-Item -Force $shimPath -ErrorAction SilentlyContinue
            Write-Host "  已删除: $shimPath" -ForegroundColor Gray
        }
    }
}

Write-Done "CLI 已卸载"

# ============================================================
# 3. 删除所有相关目录和文件
# ============================================================
Write-Step "删除文件..."

# OpenClaw 主目录
$pathsToDelete = @(
    "$env:USERPROFILE\.openclaw",
    "$env:OPENCLAW_STATE_DIR",
    "$env:USERPROFILE\.claude\skills\anthropics",
    "$env:LOCALAPPDATA\openclaw",
    "$env:APPDATA\openclaw",
    "$env:USERPROFILE\.moltbot"  # Skills CLI 创建的目录
)

foreach ($path in $pathsToDelete) {
    if ($path -and (Test-Path $path)) {
        Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
    }
}

# 删除包含 openclaw 的技能目录
$skillsDir = "$env:USERPROFILE\.claude\skills"
if (Test-Path $skillsDir) {
    Get-ChildItem -Path $skillsDir -Directory -Filter "*openclaw*" -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 删除网关脚本
$gatewayCmd = "$env:USERPROFILE\.openclaw\gateway.cmd"
if (Test-Path $gatewayCmd) {
    Remove-Item -Force $gatewayCmd -ErrorAction SilentlyContinue
}

Write-Done "文件已删除"

# ============================================================
# 完成
# ============================================================
Write-Host ""
Write-Host "========== 卸载完成 ==========" -ForegroundColor Green
Write-Host ""

# 验证
if (Get-Command openclaw -ErrorAction SilentlyContinue) {
    Write-Host "警告: openclaw 命令仍然存在" -ForegroundColor Red
} else {
    Write-Host "openclaw 命令已移除" -ForegroundColor Green
}

$openclawDir = "$env:USERPROFILE\.openclaw"
if (Test-Path $openclawDir) {
    Write-Host "警告: $openclawDir 目录仍然存在" -ForegroundColor Red
} else {
    Write-Host "$openclawDir 目录已删除" -ForegroundColor Green
}

# ============================================================
# 5. 重启终端
# ============================================================
Write-Host ""
Write-Step "重启终端..."
Start-Sleep -Seconds 1

# 启动新的 PowerShell 窗口并关闭当前窗口
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Write-Host '终端已重启' -ForegroundColor Green"
exit
