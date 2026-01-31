#Requires -Version 5.1
<#
.SYNOPSIS
    OpenClaw 一键安装脚本 (Windows)
.DESCRIPTION
    自动安装 Git, Node.js (LTS), pnpm, OpenClaw 及飞书插件
    支持有/无 winget 的环境
    无需重启终端
#>

# 设置编码和错误处理
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# ============================================================
# 辅助函数
# ============================================================

function Write-Step { param($msg) Write-Host "`n[步骤] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[成功] $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "[警告] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[错误] $msg" -ForegroundColor Red }

# 刷新当前会话的 PATH 环境变量（核心：避免重启终端）
function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"

    # 额外添加常见安装路径
    $extraPaths = @(
        "$env:ProgramFiles\Git\cmd",
        "$env:ProgramFiles\nodejs",
        "$env:LOCALAPPDATA\pnpm",
        "$env:APPDATA\npm"
    )
    foreach ($p in $extraPaths) {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
            $env:Path = "$p;$env:Path"
        }
    }
}

# 检查命令是否存在
function Test-Command {
    param($cmd)
    Refresh-Path
    $null = Get-Command $cmd -ErrorAction SilentlyContinue
    return $?
}

# 检查 winget 是否可用
function Test-Winget {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# 获取系统架构
function Get-SystemArch {
    if ([Environment]::Is64BitOperatingSystem) {
        if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
            return "arm64"
        }
        return "x64"
    }
    return "x86"
}

# 下载文件
function Download-File {
    param($url, $output)
    Write-Host "  下载中: $url" -ForegroundColor Gray

    # 使用 TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    try {
        Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing
        return $true
    } catch {
        Write-Err "下载失败: $_"
        return $false
    }
}

# ============================================================
# 安装函数
# ============================================================

# 使用 winget 安装 Git
function Install-Git-Winget {
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
}

# 直接下载安装 Git
function Install-Git-Direct {
    Write-Host "  正在获取 Git 最新版本..." -ForegroundColor Gray

    $arch = Get-SystemArch
    $tempDir = "$env:TEMP\openclaw-install"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    # 获取最新版本
    $releasesUrl = "https://api.github.com/repos/git-for-windows/git/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $releasesUrl -UseBasicParsing
        $version = $release.tag_name -replace 'v', '' -replace '\.windows\.\d+', ''

        # 查找对应架构的安装包
        $assetName = if ($arch -eq "x64") { "64-bit.exe" } else { "32-bit.exe" }
        $asset = $release.assets | Where-Object { $_.name -like "*$assetName" -and $_.name -like "*Git-*" } | Select-Object -First 1

        if (-not $asset) {
            throw "未找到适合的安装包"
        }

        $installerPath = "$tempDir\git-installer.exe"
        if (-not (Download-File $asset.browser_download_url $installerPath)) {
            throw "下载失败"
        }

        Write-Host "  正在安装 Git（静默模式）..." -ForegroundColor Gray
        Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS" -Wait

        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        Write-Err "Git 安装失败: $_"
        return $false
    }
}

# 使用 winget 安装 Node.js
function Install-Node-Winget {
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements
}

# 直接下载安装 Node.js
function Install-Node-Direct {
    Write-Host "  正在获取 Node.js LTS 版本信息..." -ForegroundColor Gray

    $arch = Get-SystemArch
    $tempDir = "$env:TEMP\openclaw-install"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    try {
        # 获取 LTS 版本
        $versionsUrl = "https://nodejs.org/dist/index.json"
        $versions = Invoke-RestMethod -Uri $versionsUrl -UseBasicParsing
        $ltsVersion = $versions | Where-Object { $_.lts -ne $false } | Select-Object -First 1
        $version = $ltsVersion.version

        Write-Host "  最新 LTS 版本: $version" -ForegroundColor Gray

        # 构建下载 URL
        $archSuffix = if ($arch -eq "arm64") { "arm64" } elseif ($arch -eq "x64") { "x64" } else { "x86" }
        $msiUrl = "https://nodejs.org/dist/$version/node-$version-$archSuffix.msi"

        $installerPath = "$tempDir\node-installer.msi"
        if (-not (Download-File $msiUrl $installerPath)) {
            throw "下载失败"
        }

        Write-Host "  正在安装 Node.js（静默模式）..." -ForegroundColor Gray
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", $installerPath, "/qn", "/norestart" -Wait

        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        Write-Err "Node.js 安装失败: $_"
        return $false
    }
}

# ============================================================
# 主脚本开始
# ============================================================

Write-Host @"

  ╔═══════════════════════════════════════════════════════╗
  ║         OpenClaw 一键安装脚本 (Windows)               ║
  ║                                                       ║
  ║  将自动安装: Git, Node.js (LTS), pnpm, OpenClaw       ║
  ╚═══════════════════════════════════════════════════════╝

"@ -ForegroundColor Magenta

# 检测安装方式
$useWinget = Test-Winget
if ($useWinget) {
    Write-Host "[信息] 检测到 winget，将使用 winget 安装" -ForegroundColor Gray
} else {
    Write-Host "[信息] 未检测到 winget，将使用直接下载安装" -ForegroundColor Gray
}

# ============================================================
# 步骤 1: 安装 Git
# ============================================================
Write-Step "检查 Git..."

if (Test-Command "git") {
    $gitVersion = git --version
    Write-Success "Git 已安装: $gitVersion"
} else {
    Write-Host "正在安装 Git..." -ForegroundColor Yellow

    $installed = $false
    if ($useWinget) {
        Install-Git-Winget
        Refresh-Path
        $installed = Test-Command "git"
    }

    if (-not $installed) {
        if ($useWinget) { Write-Warning "winget 安装失败，尝试直接下载..." }
        $installed = Install-Git-Direct
        Refresh-Path
        $installed = Test-Command "git"
    }

    if ($installed) {
        Write-Success "Git 安装完成"
    } else {
        Write-Err "Git 安装失败，请手动安装: https://git-scm.com/download/win"
        exit 1
    }
}

# ============================================================
# 步骤 2: 安装 Node.js (LTS)
# ============================================================
Write-Step "检查 Node.js..."

$needInstallNode = $true

if (Test-Command "node") {
    $nodeVersion = node --version
    $majorVersion = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')

    if ($majorVersion -ge 18) {
        Write-Success "Node.js 已安装: $nodeVersion (满足 LTS 最低要求)"
        $needInstallNode = $false
    } else {
        Write-Warning "当前 Node.js 版本 $nodeVersion 过低，将升级到 LTS 版本..."
    }
}

if ($needInstallNode) {
    Write-Host "正在安装 Node.js LTS..." -ForegroundColor Yellow

    $installed = $false
    if ($useWinget) {
        Install-Node-Winget
        Refresh-Path
        $installed = Test-Command "node"
    }

    if (-not $installed) {
        if ($useWinget) { Write-Warning "winget 安装失败，尝试直接下载..." }
        $installed = Install-Node-Direct
        Refresh-Path
        $installed = Test-Command "node"
    }

    if ($installed) {
        $nodeVersion = node --version
        Write-Success "Node.js 安装完成: $nodeVersion"
    } else {
        Write-Err "Node.js 安装失败，请手动安装: https://nodejs.org/"
        exit 1
    }
}

# ============================================================
# 步骤 3: 安装 pnpm
# ============================================================
Write-Step "检查 pnpm..."

if (Test-Command "pnpm") {
    $pnpmVersion = pnpm --version
    Write-Success "pnpm 已安装: v$pnpmVersion"
} else {
    Write-Host "正在安装 pnpm..." -ForegroundColor Yellow

    # 使用官方推荐的安装方式（不依赖 winget）
    Invoke-WebRequest https://get.pnpm.io/install.ps1 -UseBasicParsing | Invoke-Expression

    # pnpm 安装后需要设置 PATH
    $pnpmHome = "$env:LOCALAPPDATA\pnpm"
    if (Test-Path $pnpmHome) {
        $env:PNPM_HOME = $pnpmHome
        $env:Path = "$pnpmHome;$env:Path"
    }

    Refresh-Path

    if (Test-Command "pnpm") {
        $pnpmVersion = pnpm --version
        Write-Success "pnpm 安装完成: v$pnpmVersion"
    } else {
        Write-Err "pnpm 安装失败"
        Write-Host "请尝试手动安装: npm install -g pnpm" -ForegroundColor Yellow
        exit 1
    }
}

# ============================================================
# 步骤 4: 安装 OpenClaw
# ============================================================
Write-Step "检查 OpenClaw..."

if (Test-Command "openclaw") {
    Write-Success "OpenClaw 已安装"
} else {
    Write-Host "正在安装 OpenClaw..." -ForegroundColor Yellow
    pnpm add -g openclaw

    Refresh-Path

    if (Test-Command "openclaw") {
        Write-Success "OpenClaw 安装完成"
    } else {
        Write-Err "OpenClaw 安装失败"
        exit 1
    }
}

# ============================================================
# 步骤 5: 安装飞书插件
# ============================================================
Write-Step "安装飞书插件..."

openclaw plugins install @m1heng-clawd/feishu

Write-Success "飞书插件安装完成"

# ============================================================
# 完成
# ============================================================
Write-Host @"

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

"@ -ForegroundColor Green

# 显示版本信息
Write-Host "已安装版本:" -ForegroundColor Cyan
Write-Host "  Git:      $(git --version)"
Write-Host "  Node.js:  $(node --version)"
Write-Host "  pnpm:     v$(pnpm --version)"
Write-Host "  OpenClaw: $(openclaw --version 2>$null || echo '已安装')"

# ============================================================
# 可选: 安装文件处理技能
# ============================================================
Write-Host ""
Write-Host "────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""

# 检查是否在非交互模式下运行（CI 或管道）
$isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
$installSkills = $false

if ($isInteractive) {
    # 交互模式：询问用户
    Write-Host "是否需要安装 PDF, PPT, Excel, Docx 等文件处理技能？" -ForegroundColor Yellow
    Write-Host "这将安装 Python 3.12 和相关技能包"
    Write-Host ""
    $response = Read-Host "安装文件处理技能? (y/N)"
    $installSkills = $response -match '^[Yy]$'
} else {
    # 非交互模式：检查环境变量
    $installSkills = $env:INSTALL_SKILLS -eq 'y'
}

if ($installSkills) {
    Write-Step "安装文件处理技能..."

    # 检查并安装 Python 3.12
    Write-Step "检查 Python..."

    $needInstallPython = $true
    $pythonCmd = ""

    # 检查 Python 版本
    if (Test-Command "python") {
        try {
            $pythonVersion = python --version 2>&1
            $versionMatch = [regex]::Match($pythonVersion, 'Python (\d+)\.(\d+)')
            if ($versionMatch.Success) {
                $major = [int]$versionMatch.Groups[1].Value
                $minor = [int]$versionMatch.Groups[2].Value
                if ($major -eq 3 -and $minor -ge 12) {
                    Write-Success "Python 已安装: $pythonVersion"
                    $pythonCmd = "python"
                    $needInstallPython = $false
                } else {
                    Write-Warning "当前 Python 版本 $pythonVersion 过低，将安装 Python 3.12..."
                }
            }
        } catch {
            # Python 命令失败，需要安装
        }
    }

    if ($needInstallPython) {
        Write-Host "正在安装 Python 3.12..." -ForegroundColor Yellow

        $installed = $false
        if ($useWinget) {
            winget install --id Python.Python.3.12 -e --source winget --accept-package-agreements --accept-source-agreements
            Refresh-Path
            $installed = Test-Command "python"
        }

        if (-not $installed) {
            # 直接下载安装
            Write-Host "  正在下载 Python 3.12..." -ForegroundColor Gray
            $arch = Get-SystemArch
            $tempDir = "$env:TEMP\openclaw-install"
            New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

            try {
                $pythonArch = if ($arch -eq "arm64") { "arm64" } elseif ($arch -eq "x64") { "amd64" } else { "win32" }
                $pythonUrl = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-$pythonArch.exe"

                $installerPath = "$tempDir\python-installer.exe"
                if (Download-File $pythonUrl $installerPath) {
                    Write-Host "  正在安装 Python 3.12（静默模式）..." -ForegroundColor Gray
                    Start-Process -FilePath $installerPath -ArgumentList "/quiet", "InstallAllUsers=0", "PrependPath=1", "Include_test=0" -Wait
                    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                    $installed = $true
                }
            } catch {
                Write-Err "Python 下载安装失败: $_"
            }
        }

        Refresh-Path

        # 添加 Python 到 PATH
        $pythonPaths = @(
            "$env:LOCALAPPDATA\Programs\Python\Python312",
            "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts",
            "$env:ProgramFiles\Python312",
            "$env:ProgramFiles\Python312\Scripts"
        )
        foreach ($p in $pythonPaths) {
            if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
                $env:Path = "$p;$env:Path"
            }
        }

        if (Test-Command "python") {
            $pythonVersion = python --version 2>&1
            Write-Success "Python 3.12 安装完成: $pythonVersion"
            $pythonCmd = "python"
        } else {
            Write-Err "Python 3.12 安装失败，请手动安装: https://www.python.org/downloads/"
            exit 1
        }
    }

    # 安装文件处理技能
    Write-Step "安装 PDF, PPT, Excel, Docx 技能..."
    npx add-skill anthropics/skills --skill xlsx --skill pdf --skill pptx --skill docx

    Write-Success "文件处理技能安装完成"

    Write-Host ""
    Write-Host "已安装技能:" -ForegroundColor Cyan
    Write-Host "  - xlsx (Excel 文件处理)"
    Write-Host "  - pdf (PDF 文件处理)"
    Write-Host "  - pptx (PowerPoint 文件处理)"
    Write-Host "  - docx (Word 文件处理)"
}
