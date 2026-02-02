#Requires -Version 5.1
<#
.SYNOPSIS
    OpenClaw 一键安装脚本 (Windows)
.DESCRIPTION
    自动安装 Git, Node.js (LTS), OpenClaw 及飞书插件
    支持有/无 winget 的环境
    无需重启终端
#>

# 设置控制台为 UTF-8 编码（解决中文乱码）
try {
    chcp 65001 | Out-Null
} catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# 设置编码和错误处理
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# ============================================================
# 版本配置 (Versions)
# ============================================================
$verOpenClaw = "2026.1.30"
$verFeishu = "0.1.6"
$verSkills = "1.3.1"
$verClipboard = "0.3.2"
$verTag = "1.0.1" # Gitee Release Tag

# ============================================================
# NPM 镜像源测速与选择（并发测试）
# ============================================================
$script:originalNpmRegistry = ""
$script:selectedNpmRegistry = ""

# 并发选择最快的可用 NPM 镜像源
# 简单的串行测速（更稳定，避免多线程 Runspace 报错）
function Select-BestNpmRegistry {
    Write-Step "测试 NPM 镜像源..."

    $taobao = "https://registry.npmmirror.com/"
    $official = "https://registry.npmjs.org/"
    
    # 优先测试淘宝源
    Write-Host "  正在连接淘宝源..." -NoNewline
    try {
        $request = [System.Net.WebRequest]::Create("${taobao}lodash")
        $request.Timeout = 3000 # 3秒超时
        $request.Method = "HEAD"
        $response = $request.GetResponse()
        if ($response.StatusCode -eq "OK") {
            Write-Host " [OK]" -ForegroundColor Green
            $script:selectedNpmRegistry = $taobao
            npm config set registry $taobao 2>$null
            Write-Success "已选择: 淘宝源"
            return
        }
    } catch {
        Write-Host " [超时/失败]" -ForegroundColor Red
    }

    # 如果淘宝失败，测试官方源
    Write-Host "  正在连接官方源..." -NoNewline
    try {
        $request = [System.Net.WebRequest]::Create("${official}lodash")
        $request.Timeout = 5000
        $request.Method = "HEAD"
        $response = $request.GetResponse()
        if ($response.StatusCode -eq "OK") {
            Write-Host " [OK]" -ForegroundColor Green
            $script:selectedNpmRegistry = $official
            npm config set registry $official 2>$null
            Write-Success "已选择: 官方源"
            return
        }
    } catch {
        Write-Host " [超时/失败]" -ForegroundColor Red
    }

    # 保底
    Write-Warning "所有镜像源检测失败，强制使用淘宝源"
    $script:selectedNpmRegistry = $taobao
    npm config set registry $taobao 2>$null
}

function Restore-NpmRegistry {
    try {
        if ($script:originalNpmRegistry -and $script:originalNpmRegistry -ne "undefined" -and $script:originalNpmRegistry -ne $script:selectedNpmRegistry) {
            npm config set registry $script:originalNpmRegistry 2>$null
        } else {
            npm config set registry https://registry.npmjs.org 2>$null
        }
        Write-Host "[信息] 已恢复 npm 源设置" -ForegroundColor Gray
    } catch {}
}

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
        "${env:ProgramFiles(x86)}\nodejs",
        "$env:LOCALAPPDATA\pnpm",
        "$env:APPDATA\npm",
        "$env:ProgramData\chocolatey\bin",
        "$env:ChocolateyInstall\bin"
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

# 检查 Chocolatey 是否可用
function Test-Choco {
    try {
        $null = Get-Command choco -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# 安装 Chocolatey（一键安装，无需用户交互）
function Install-Chocolatey {
    Write-Host "  正在安装 Chocolatey 包管理器..." -ForegroundColor Gray
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        # 刷新 PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        return Test-Choco
    } catch {
        Write-Err "Chocolatey 安装失败: $_"
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
# GitHub 镜像源测速与选择
# ============================================================
# ============================================================
# GitHub 镜像源测速与选择（并发测试）
# ============================================================

# 简单的串行测速（GitHub 镜像）
function Select-BestMirror {
   Write-Step "测试 GitHub 镜像源..."

   $mirrorUrl = "https://openclaw.mintmind.io/https://github.com/"
   $testUrl = "https://openclaw.mintmind.io/https://github.com/npm/cli/raw/latest/README.md"
   
   Write-Host "  正在连接 openclaw-proxy..." -NoNewline
   try {
       $request = [System.Net.WebRequest]::Create($testUrl)
       $request.Timeout = 5000 # 5秒超时
       $request.Method = "HEAD"
       $response = $request.GetResponse()
       if ($response.StatusCode -eq "OK") {
           Write-Host " [OK]" -ForegroundColor Green
           Write-Success "已选择: openclaw-proxy"
           return $mirrorUrl
       }
   } catch {
       Write-Host " [超时/失败]" -ForegroundColor Red
   }

   Write-Warning "所有镜像源检测失败，将直接连接 GitHub"
   return ""
}

# 应用镜像配置
function Apply-GitMirror {
    param($mirrorUrl)

    if ([string]::IsNullOrEmpty($mirrorUrl)) {
        return
    }

    # 辅助函数：配置单个镜像的所有 URL 重定向
    # 注意：使用 --add 来添加多个 insteadOf 值，而不是覆盖
    function Set-MirrorConfig {
        param($mirrorPrefix)
        # 先清除可能存在的旧配置
        git config --global --unset-all url."$mirrorPrefix".insteadOf 2>$null
        # HTTPS URL（使用 --add 添加第一个）
        git config --global --add url."$mirrorPrefix".insteadOf "https://github.com/"
        # SSH URL (npm 的 git 依赖使用这种格式)
        git config --global --add url."$mirrorPrefix".insteadOf "ssh://git@github.com/"
        # Git SSH 短格式
        git config --global --add url."$mirrorPrefix".insteadOf "git@github.com:"
    }

    # 根据镜像 URL 直接配置对应的 insteadOf
    if ($mirrorUrl -like "*mintmind.io*") {
        Set-MirrorConfig "https://openclaw.mintmind.io/https://github.com/"
    } elseif ($mirrorUrl -like "*ghfast.top*") {
        Set-MirrorConfig "https://ghfast.top/https://github.com/"
    } elseif ($mirrorUrl -like "*kkgithub.com*") {
        Set-MirrorConfig "https://kkgithub.com/"
    } elseif ($mirrorUrl -like "*gitmirror.com*") {
        Set-MirrorConfig "https://hub.gitmirror.com/"
    } elseif ($mirrorUrl -like "*ghproxy.com*") {
        Set-MirrorConfig "https://mirror.ghproxy.com/https://github.com/"
    } elseif ($mirrorUrl -like "*gh.qninq.cn*") {
        Set-MirrorConfig "https://gh.qninq.cn/https://github.com/"
    } elseif ($mirrorUrl -like "*gh.api.99988866.xyz*") {
        Set-MirrorConfig "https://gh.api.99988866.xyz/https://github.com/"
    } elseif ($mirrorUrl -like "*github.moeyy.xyz*") {
        Set-MirrorConfig "https://github.moeyy.xyz/https://github.com/"
    } elseif ($mirrorUrl -like "*gh-proxy.com*") {
        Set-MirrorConfig "https://gh-proxy.com/https://github.com/"
    } else {
        Set-MirrorConfig "$mirrorUrl"
    }
}

# 清除镜像配置
function Remove-GitMirror {
    # 所有镜像前缀
    # 只保留最有效的镜像源
    $mirrorPrefixes = @(
        "https://openclaw.mintmind.io/https://github.com/",
        "https://openclaw-gh-proxy.dejuanrohan1.workers.dev/https://github.com/",
        "https://ghfast.top/https://github.com/",
        "https://kkgithub.com/",
        "https://hub.gitmirror.com/",
        "https://mirror.ghproxy.com/https://github.com/",
        "https://gh.qninq.cn/https://github.com/",
        "https://gh.api.99988866.xyz/https://github.com/",
        "https://github.moeyy.xyz/https://github.com/",
        "https://gh-proxy.com/https://github.com/",
        "https://gitclone.com/github.com/",
        "https://bgithub.xyz/"
    )

    # 清除所有可能的镜像配置（包括 HTTPS、SSH 和 git@ 格式）
    foreach ($prefix in $mirrorPrefixes) {
        git config --global --unset-all "url.$prefix.insteadOf" 2>$null
    }

    # 额外清除可能的 SSH 和 git@ 格式的源地址配置
    # 这些是 insteadOf 的值，不是 key，所以需要用 --unset-all 匹配
    git config --global --unset-all url.*.insteadOf "ssh://git@github.com/" 2>$null
    git config --global --unset-all url.*.insteadOf "git@github.com:" 2>$null
}

# ============================================================
# 安装函数
# ============================================================

# 使用 winget 安装 Git
function Install-Git-Winget {
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements 2>$null
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
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements 2>$null
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
  ║    金牌小密探😎 OpenClaw 一键安装脚本 (Windows)       ║
  ║                                                       ║
  ║  将自动安装: Git, Node.js, Python, OpenClaw           ║
  ╚═══════════════════════════════════════════════════════╝

"@ -ForegroundColor Magenta

# 检测安装方式
$useWinget = Test-Winget
$useChoco = Test-Choco

if ($useWinget) {
    Write-Host "[信息] 检测到 winget，将使用 winget 安装" -ForegroundColor Gray
} elseif ($useChoco) {
    Write-Host "[信息] 检测到 Chocolatey，将使用 choco 安装" -ForegroundColor Gray
} else {
    Write-Host "[信息] 未检测到 winget，正在安装 Chocolatey..." -ForegroundColor Gray
    if (Install-Chocolatey) {
        $useChoco = $true
        Write-Success "Chocolatey 安装完成"
    } else {
        Write-Warning "Chocolatey 安装失败，将使用直接下载安装"
    }
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

    # 优先使用 winget
    if ($useWinget) {
        Install-Git-Winget
        Refresh-Path
        $installed = Test-Command "git"
    }

    # 其次使用 Chocolatey
    if (-not $installed -and $useChoco) {
        if ($useWinget) { Write-Warning "winget 安装失败，尝试使用 Chocolatey..." }
        choco install git -y 2>$null
        Refresh-Path
        $installed = Test-Command "git"
    }

    # 最后直接下载
    if (-not $installed) {
        Write-Warning "尝试直接下载安装..."
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

    # 优先使用 winget
    if ($useWinget) {
        Install-Node-Winget
        Refresh-Path
        $installed = Test-Command "node"
    }

    # 其次使用 Chocolatey
    if (-not $installed -and $useChoco) {
        if ($useWinget) { Write-Warning "winget 安装失败，尝试使用 Chocolatey..." }
        choco install nodejs-lts -y 2>$null
        Refresh-Path
        $installed = Test-Command "node"
    }

    # 最后直接下载
    if (-not $installed) {
        Write-Warning "尝试直接下载安装..."
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
# 注：GitHub 镜像配置已移至回退机制，核心安装不再需要 GitHub
# ============================================================

# ============================================================
# 步骤 3.5: 选择最佳 NPM 镜像源
# ============================================================
Select-BestNpmRegistry

# ============================================================
# 步骤 4: 安装 OpenClaw
# ============================================================
# ============================================================
# 步骤 4: 安装 OpenClaw (Gitee 稳定版)
# ============================================================
Write-Step "检查 OpenClaw..."

# 1. 检测 Node.js 运行时架构 (最准确)
Write-Host "  正在检测 Node.js 架构..." -ForegroundColor Gray
try {
    $arch = cmd /c "node -p process.arch" 2>$null
    $arch = $arch.Trim()
} catch {
    $arch = ""
}

if ([string]::IsNullOrWhiteSpace($arch)) {
    # 回退到环境变量检测
    Write-Warning "无法通过 Node.js 检测架构，尝试环境变量..."
    $sysArch = $env:PROCESSOR_ARCHITECTURE
    if ($sysArch -eq "AMD64") {
        $arch = "x64"
    } elseif ($sysArch -eq "ARM64") {
        $arch = "arm64"
    } else {
        $arch = "x64" # 默认回退
    }
}

Write-Host "  目标架构: $arch" -ForegroundColor Gray

# 1.5 检查并安装 VC++ 运行库 (对原生模块至关重要)
Write-Host "  正在检查运行环境..." -ForegroundColor Gray
$vcRedistUrl = ""
if ($arch -eq "arm64") {
    $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.arm64.exe"
} else {
    $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
}

# 简单粗暴但有效：直接静默安装。安装程序会自动检测，如果已安装则会快速退出。
Write-Host "  正在准备 VC++ 运行库 (可能需要几分钟)..." -ForegroundColor Gray
$vcRedistPath = "$env:TEMP\vc_redist.exe"

try {
    # 始终尝试下载最新版
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($vcRedistUrl, $vcRedistPath)
    
    if (Test-Path $vcRedistPath) {
        Write-Host "  正在配置系统环境 (VC++ Redist)..." -ForegroundColor Gray
        # /install /quiet /norestart
        $process = Start-Process -FilePath $vcRedistPath -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
        
        # 0 = 成功, 1638 = 已安装更新版本, 3010 = 需要重启
        if ($process.ExitCode -eq 0) {
             Write-Success "环境配置完成"
        } elseif ($process.ExitCode -eq 1638) {
             Write-Host "  环境已就绪 (已安装)" -ForegroundColor Gray
        } elseif ($process.ExitCode -eq 3010) {
             Write-Warning "环境配置完成 (需要重启生效)"
        } else {
             # 仅记录警告，不中断流程，因为可能是误报或已有环境
             Write-Warning "环境配置返回代码: $($process.ExitCode)"
        }
        
        Remove-Item -Path $vcRedistPath -Force -ErrorAction SilentlyContinue
    }
} catch {
    # 网络错误不应阻断安装，用户可能已经安装了
    Write-Host "  跳过环境自动配置 (网络原因)，继续安装..." -ForegroundColor Gray
}

# 2. Gitee 包链接
$BaseUrl = "https://gitee.com/mintmind/openclaw-packages/releases/download/$verTag"
$OpenclawUrl = "$BaseUrl/openclaw-$verOpenClaw.tgz"
$ClipboardUrl_x64 = "$BaseUrl/mariozechner-clipboard-win32-x64-msvc-$verClipboard.tgz"
$ClipboardUrl_arm64 = "$BaseUrl/mariozechner-clipboard-win32-arm64-msvc-$verClipboard.tgz"

# 选择对应的 clipboard 包
if ($arch -eq "arm64") {
    $ClipboardUrl = $ClipboardUrl_arm64
} else {
    $ClipboardUrl = $ClipboardUrl_x64
}

# 检测是否需要重新安装
$needInstall = $true
if (Test-Command "openclaw") {
    # 验证是否可运行
    try {
        $null = cmd /c "openclaw --version" 2>&1
        if ($LASTEXITCODE -eq 0) {
            # 检查版本匹配
            $currentVer = openclaw --version
            if ($currentVer -like "*$verOpenClaw*") {
                $needInstall = $false
                Write-Success "OpenClaw 已安装且版本匹配 ($verOpenClaw)"
            } else {
                Write-Warning "版本不匹配 (当前: $currentVer, 目标: $verOpenClaw)，准备升级..."
            }
        } else {
            Write-Warning "检测到 OpenClaw 安装损坏，准备重新安装..."
        }
    } catch {
        Write-Warning "检测到 OpenClaw 安装损坏，准备重新安装..."
    }
} else {
    Write-Host "正在安装 OpenClaw (从 Gitee 下载)..." -ForegroundColor Yellow
}

if ($needInstall) {
    # 3. 清理旧安装
    $openclawDir = "$env:APPDATA\npm\node_modules\openclaw"
    if (Test-Path $openclawDir) {
        Write-Host "  清理旧安装文件..." -ForegroundColor Gray
        Remove-Item -Recurse -Force $openclawDir -ErrorAction SilentlyContinue
    }
    # 清理 shim
    @("openclaw", "openclaw.cmd", "openclaw.ps1") | ForEach-Object {
        $shimPath = "$env:APPDATA\npm\$_"
        if (Test-Path $shimPath) { Remove-Item -Force $shimPath -ErrorAction SilentlyContinue }
    }

    # 4. 下载 OpenClaw
    $OpenclawTmp = "$env:TEMP\openclaw.tgz"
    Write-Host "  正在下载 OpenClaw (Gitee)..." -ForegroundColor Gray
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($OpenclawUrl, $OpenclawTmp)
    } catch {
        Write-Err "OpenClaw 下载失败: $_"
        exit 1
    }

    # 5. 安装 OpenClaw (跳过脚本)
    Write-Host "  正在安装 OpenClaw核心 (跳过编译)..." -ForegroundColor Gray
    $ErrorActionPreference = "Continue"
    cmd /c "npm install -g `"$OpenclawTmp`" --registry=https://registry.npmmirror.com --ignore-scripts --progress --loglevel=notice"
    $ErrorActionPreference = "Stop"
    Remove-Item -Path $OpenclawTmp -Force -ErrorAction SilentlyContinue

    Refresh-Path
    
    # 6. 后处理：移除 node-llama-cpp 和修复 native 模块
    if (Test-Path $openclawDir) {
        # 6.1 移除 node-llama-cpp (不需要本地 LLM)
        $nodeLlamaCppDir = "$openclawDir\node_modules\node-llama-cpp"
        if (Test-Path $nodeLlamaCppDir) {
            Write-Host "  清理无用模块 (node-llama-cpp)..." -ForegroundColor Gray
            Remove-Item -Recurse -Force $nodeLlamaCppDir -ErrorAction SilentlyContinue
        }

        # 6.2 手动安装 clipboard 模块 (native)
        Write-Host "  安装剪贴板支持 ($arch native)..." -ForegroundColor Gray
        $ClipboardTmp = "$env:TEMP\clipboard.tgz"
        try {
            $webClient.DownloadFile($ClipboardUrl, $ClipboardTmp)
            
            # 安装到 openclaw 的 node_modules
            if (Test-Path $ClipboardTmp) {
                Push-Location $openclawDir
                $ErrorActionPreference = "Continue"
                # --no-save 避免修改 package.json, --ignore-scripts 避免触发 postinstall
                # 但这会把包解压并替换现有的 @mariozechner/clipboard
                cmd /c "npm install `"$ClipboardTmp`" --no-save --ignore-scripts"
                $ErrorActionPreference = "Stop"
                Pop-Location
                Remove-Item -Path $ClipboardTmp -Force -ErrorAction SilentlyContinue
                Write-Success "剪贴板模块安装完成"
            }
        } catch {
            Write-Warning "剪贴板模块安装失败: $_ (可能影响剪贴板功能)"
        }
    } else {
        Write-Err "OpenClaw 目录未创建，安装可能失败"
        exit 1
    }

    # final check
    if (Test-Command "openclaw") {
        # 验证是否可以加载原生模块
        try {
            $null = cmd /c "openclaw --version" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "OpenClaw 安装完成"
            } else {
                Write-Err "OpenClaw 安装完成但无法启动"
                Write-Host ""
                Write-Host "可能原因: 缺少 VC++ 运行库" -ForegroundColor Yellow
                Write-Host "请下载并安装 Microsoft Visual C++ Redistributable:"
                Write-Host "  https://aka.ms/vs/17/release/vc_redist.$arch.exe" -ForegroundColor Cyan
                exit 1
            }
        } catch {
             Write-Err "无法执行 openclaw --version"
        }
    } else {
        Write-Err "OpenClaw 安装失败，请检查 npm 日志"
        exit 1
    }
}


# ============================================================
# 完成
# ============================================================
Write-Host @"

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

"@ -ForegroundColor Green

# 显示版本信息
Write-Host "已安装版本:" -ForegroundColor Cyan
Write-Host "  Git:      $(git --version)"
Write-Host "  Node.js:  $(node --version)"
$openclawVer = (openclaw --version 2>$null)
Write-Host "  OpenClaw: $(if ($openclawVer) { $openclawVer } else { '已安装' })"

# ============================================================
# 安装文件处理技能
# ============================================================
Write-Host ""
Write-Host "────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""

# 默认安装文件处理技能（可通过 SKIP_SKILLS=1 跳过）
if ($env:SKIP_SKILLS -ne "1") {
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

        # 优先使用 winget
        if ($useWinget) {
            winget install --id Python.Python.3.12 -e --source winget --accept-package-agreements --accept-source-agreements 2>$null
            Refresh-Path
            $installed = Test-Command "python"
        }

        # 其次使用 Chocolatey
        if (-not $installed -and $useChoco) {
            if ($useWinget) { Write-Warning "winget 安装失败，尝试使用 Chocolatey..." }
            choco install python312 -y 2>$null
            Refresh-Path
            $installed = Test-Command "python"
        }

        # 最后直接下载
        if (-not $installed) {
            Write-Warning "尝试直接下载安装..."
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

    # 临时配置 Git 镜像以解决 GitHub 访问问题
    $skillsMirror = Select-BestMirror
    Apply-GitMirror $skillsMirror
    
    # 修复 skills CLI 的 bug: 它尝试在 HOME/.moltbot 创建目录但不检查父目录是否存在
    # 修复 skills CLI 的 bug: 它尝试在 HOME/.moltbot 创建目录但不检查父目录是否存在
    $moltbotDir = "$env:USERPROFILE\.moltbot"
    if (Test-Path $moltbotDir) {
        $item = Get-Item $moltbotDir
        if (-not $item.PSIsContainer) {
            # 如果是文件，删除它
            Remove-Item -Force $moltbotDir
            New-Item -ItemType Directory -Force -Path $moltbotDir | Out-Null
        }
    } else {
        # 如果不存在，创建它
        New-Item -ItemType Directory -Force -Path $moltbotDir | Out-Null
    }

    npx -y skills@$verSkills add anthropics/skills --skill xlsx --skill pdf --skill pptx --skill docx --agent openclaw -y -g 2>$null

    # 恢复 Git 配置
    Remove-GitMirror
    Write-Success "Git 配置已恢复"

    Write-Success "文件处理技能安装完成"

    Write-Host ""
    Write-Host "已安装技能:" -ForegroundColor Cyan
    Write-Host "  - xlsx (Excel 文件处理)"
    Write-Host "  - pdf (PDF 文件处理)"
    Write-Host "  - pptx (PowerPoint 文件处理)"
    Write-Host "  - docx (Word 文件处理)"
}

# ============================================================
# 自动初始化 OpenClaw
# ============================================================
Write-Host ""
Write-Host "────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""

Write-Step "初始化 OpenClaw..."

# 强制停止所有残留的 openclaw 进程，避免端口冲突导致 gateway closed
Get-Process node, openclaw -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*openclaw*" } | Stop-Process -Force -ErrorAction SilentlyContinue

try {
    openclaw onboard --non-interactive --accept-risk --skip-daemon 2>&1 | Select-String -Pattern "^\s*$" -NotMatch
} catch {
    Write-Warning "初始化遇到轻微错误，尝试继续..."
}

Write-Step "安装网关服务..."
try {
    openclaw gateway install 2>&1
    Write-Success "网关服务安装完成"
} catch {
    Write-Err "网关服务安装失败"
    exit 1
}

Write-Step "配置静默启动脚本..."

# 为了实现完全静默启动（不弹窗），我们需要借助 VBScript
$daemonScript = "$env:USERPROFILE\.openclaw\daemon.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
' 0 = Hide Window, False = Do not wait for completion
WshShell.Run "openclaw gateway start", 0, False
"@
Set-Content -Path $daemonScript -Value $vbsContent -Encoding UTF8

Write-Step "启动网关服务 (后台静默)..."
try {
    # 使用 wscript 运行 vbs 实现彻底隐藏
    Start-Process wscript -ArgumentList "`"$daemonScript`"" -WindowStyle Hidden
    
    # 等待服务预热
    Start-Sleep -Seconds 5
    
    # 验证是否启动成功 (通过检查端口或进程)
    if (Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*openclaw*" -or $_.CommandLine -like "*openclaw*" }) {
         Write-Success "网关服务已在后台启动"
    } else {
         # 只要没报错，通常就是启动了 (因为是静默的，进程可能不易检测)
         Write-Success "网关服务启动指令已发送"
    }
    
    Write-Host "  提示: 您也可以通过运行以下文件手动静默启动:" -ForegroundColor Gray
    Write-Host "  $daemonScript" -ForegroundColor Gray
} catch {
    Write-Err "网关服务启动失败"
    exit 1
}

Write-Success "OpenClaw 初始化完成"

# ============================================================
# 配置飞书 Channel
# ============================================================
Write-Host ""
Write-Host "────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""
Write-Host "配置飞书机器人" -ForegroundColor Yellow
Write-Host ""
Write-Host "请输入飞书应用的 App ID 和 App Secret"
Write-Host "（可在飞书开放平台 https://open.feishu.cn 获取）"
Write-Host ""

# 读取飞书 App ID 和 App Secret（明文输入）
$feishuAppId = ""
$feishuAppSecret = ""

# 确保在用户交互时不会因为之前的错误而退出
$ErrorActionPreference = "Continue"

if ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") } # 清除缓冲区

if ([Environment]::UserInteractive) {
    try {
        Write-Host -NoNewline "飞书 App ID (直接回车跳过): " -ForegroundColor Green
        if ([Console]::IsInputRedirected) {
            $feishuAppId = $Host.UI.ReadLine()
        } else {
            $feishuAppId = Read-Host
        }

        if (-not [string]::IsNullOrWhiteSpace($feishuAppId)) {
            Write-Host -NoNewline "飞书 App Secret: " -ForegroundColor Green
            if ([Console]::IsInputRedirected) {
                $feishuAppSecret = $Host.UI.ReadLine()
            } else {
                $feishuAppSecret = Read-Host
            }
        }
    } catch {
        Write-Warning "无法读取输入，跳过..."
    }
}

if ($feishuAppId -and $feishuAppSecret) {
    Write-Step "配置飞书..."
    
    # 1. 下载并安装指定版本的飞书插件 (锁定版本)
    $FeishuUrl = "$BaseUrl/feishu-$verFeishu.tgz"
    $FeishuTmp = "$env:TEMP\feishu.tgz"
    
    Write-Host "  正在下载飞书插件 ($verFeishu)..." -ForegroundColor Gray
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($FeishuUrl, $FeishuTmp)
        
        Write-Host "  正在安装飞书插件..." -ForegroundColor Gray
        cmd /c "npm install -g `"$FeishuTmp`" --registry=https://registry.npmmirror.com --no-audit --loglevel=error"
        Remove-Item -Path $FeishuTmp -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "飞书插件下载/安装失败，尝试通过 CLI 自动安装..."
    }

    # 2. 注册并配置
    openclaw channels add --channel feishu 2>$null
    openclaw config set channels.feishu.appId $feishuAppId 2>$null
    openclaw config set channels.feishu.appSecret $feishuAppSecret 2>$null
    Write-Success "飞书配置完成"
} else {
    Write-Warning "跳过飞书配置（未输入完整信息）"
}

# ============================================================
# 配置 Qwen AI 模型
# ============================================================
Write-Host ""
Write-Host "────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""
Write-Host "配置 AI 模型 (Qwen)" -ForegroundColor Yellow
Write-Host ""
Write-Host "即将打开浏览器进行 Qwen 授权..."
Write-Host "请在浏览器中完成登录授权"
Write-Host ""

Write-Step "启动 Qwen 认证..."

# 首先启用 qwen-portal-auth plugin
openclaw plugins enable qwen-portal-auth 2>&1 | Select-String -Pattern "^\s*$" -NotMatch

# 然后进行认证
openclaw models auth login --provider qwen-portal --set-default

# 复制 auth 配置到主 agent 目录
$agentAuthPath = "$env:USERPROFILE\.openclaw\agents\main\agent\auth-profiles.json"
$mainAuthPath = "$env:USERPROFILE\.openclaw\agents\main\auth-profiles.json"
if (Test-Path $agentAuthPath) {
    Copy-Item $agentAuthPath $mainAuthPath -Force
}

# 重启 gateway 使配置生效
Write-Step "重启网关服务..."
openclaw gateway restart 2>&1 | Select-String -Pattern "^\s*$" -NotMatch

Write-Success "Qwen 认证完成"

# ============================================================
# 恢复 npm 源设置
# ============================================================
Restore-NpmRegistry

# ============================================================
# 完成
# ============================================================
Write-Host ""
Write-Host "────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                     配置完成!                         ║" -ForegroundColor Green
Write-Host "  ╠═══════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "  ║                                                       ║" -ForegroundColor Green
Write-Host "  ║  OpenClaw 已准备就绪!                                 ║" -ForegroundColor Green
Write-Host "  ║                                                       ║" -ForegroundColor Green
Write-Host "  ║  常用命令:                                            ║" -ForegroundColor Green
Write-Host "  ║    openclaw dashboard   - 打开控制台 (浏览器)     ║" -ForegroundColor Green
Write-Host "  ║    openclaw gateway restart - 重启服务                ║" -ForegroundColor Green
Write-Host "  ║    openclaw gateway stop    - 停止服务                ║" -ForegroundColor Green
Write-Host "  ║                                                       ║" -ForegroundColor Green
Write-Host "  ║  本地地址: http://127.0.0.1:18789/__openclaw__/canvas/║" -ForegroundColor Green
Write-Host "  ║                                                       ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
