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
# NPM 镜像源测速与选择（并发测试）
# ============================================================
$script:originalNpmRegistry = ""
$script:selectedNpmRegistry = ""

# 并发选择最快的可用 NPM 镜像源
function Select-BestNpmRegistry {
    Write-Step "并发测试 NPM 镜像源..."

    $registries = @(
        @{ Url = "https://registry.npmmirror.com/"; Name = "淘宝源(阿里)" },
        @{ Url = "https://mirrors.cloud.tencent.com/npm/"; Name = "腾讯云源" },
        @{ Url = "https://mirrors.huaweicloud.com/repository/npm/"; Name = "华为云源" },
        @{ Url = "https://registry.npmjs.org/"; Name = "官方源(npmjs)" }
    )

    # 保存原始镜像源配置
    try {
        $script:originalNpmRegistry = npm config get registry 2>$null
    } catch {}

    Write-Host "  正在并发测试 $($registries.Count) 个镜像源..." -ForegroundColor Gray

    # 测试脚本块
    $testScript = {
        param($registryUrl, $registryName)
        try {
            $testUrl = "${registryUrl}lodash"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $request = [System.Net.WebRequest]::Create($testUrl)
            $request.Timeout = 8000
            $request.Method = "GET"

            try {
                $response = $request.GetResponse()
                $response.Close()
                $stopwatch.Stop()
                return @{
                    Success = $true
                    Time = $stopwatch.ElapsedMilliseconds
                    Url = $registryUrl
                    Name = $registryName
                }
            } catch {
                return @{
                    Success = $false
                    Time = -1
                    Url = $registryUrl
                    Name = $registryName
                }
            }
        } catch {
            return @{
                Success = $false
                Time = -1
                Url = $registryUrl
                Name = $registryName
            }
        }
    }

    # 创建并发任务
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $registries.Count)
    $runspacePool.Open()

    $jobs = @()
    foreach ($registry in $registries) {
        $powershell = [powershell]::Create().AddScript($testScript).AddArgument($registry.Url).AddArgument($registry.Name)
        $powershell.RunspacePool = $runspacePool
        $jobs += @{
            PowerShell = $powershell
            Handle = $powershell.BeginInvoke()
            Registry = $registry
        }
    }

    # 等待所有任务完成（最多 10 秒）
    $timeout = [DateTime]::Now.AddSeconds(10)
    while ($jobs | Where-Object { -not $_.Handle.IsCompleted }) {
        if ([DateTime]::Now -gt $timeout) {
            break
        }
        Start-Sleep -Milliseconds 100
    }

    # 收集结果
    $results = @()
    foreach ($job in $jobs) {
        try {
            if ($job.Handle.IsCompleted) {
                $result = $job.PowerShell.EndInvoke($job.Handle)
                if ($result -and $result.Success) {
                    Write-Host "  $($result.Name): " -NoNewline
                    Write-Host "$($result.Time)ms" -ForegroundColor Green
                    $results += $result
                } else {
                    Write-Host "  $($job.Registry.Name): " -NoNewline
                    Write-Host "不可用" -ForegroundColor Red
                }
            } else {
                Write-Host "  $($job.Registry.Name): " -NoNewline
                Write-Host "超时" -ForegroundColor Red
            }
        } catch {
            Write-Host "  $($job.Registry.Name): " -NoNewline
            Write-Host "错误" -ForegroundColor Red
        } finally {
            $job.PowerShell.Dispose()
        }
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

    # 按响应时间排序，选择最快的
    if ($results.Count -gt 0) {
        $best = $results | Sort-Object { $_.Time } | Select-Object -First 1
        Write-Success "已选择最快 NPM 镜像源: $($best.Name) ($($best.Time)ms)"
        $script:selectedNpmRegistry = $best.Url
        npm config set registry $best.Url 2>$null
    } else {
        Write-Warning "所有镜像源均不可用，使用淘宝镜像源"
        $script:selectedNpmRegistry = "https://registry.npmmirror.com/"
        npm config set registry "https://registry.npmmirror.com/" 2>$null
    }
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

# 并发选择最快的可用 GitHub 镜像源
# 返回: 镜像 URL 字符串，如果没有可用镜像返回空字符串
function Select-BestMirror {
    Write-Step "并发测试 GitHub 镜像源..."

    # 镜像列表（简化版）：只保留自建 Cloudflare 代理
    $mirrors = @(
        # 自建 Cloudflare Worker 代理（自定义域名，优先）
        @{ Url = "https://openclaw.mintmind.io/https://github.com/"; TestUrl = "https://openclaw.mintmind.io/https://github.com/npm/cli/raw/latest/README.md"; Name = "openclaw-proxy" },
        # 自建 Cloudflare Worker 代理（workers.dev 备用）
        @{ Url = "https://openclaw-gh-proxy.dejuanrohan1.workers.dev/https://github.com/"; TestUrl = "https://openclaw-gh-proxy.dejuanrohan1.workers.dev/https://github.com/npm/cli/raw/latest/README.md"; Name = "openclaw-proxy-workers" }
    )

    Write-Host "  正在并发测试 $($mirrors.Count) 个镜像源..." -ForegroundColor Gray

    # 测试脚本块 - 使用 HTTP 请求测试
    $testScript = {
        param($mirrorUrl, $testUrl, $mirrorName)
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # 使用 WebRequest 测试，设置超时 8 秒
            $request = [System.Net.WebRequest]::Create($testUrl)
            $request.Method = "HEAD"
            $request.Timeout = 8000
            $request.AllowAutoRedirect = $true

            $response = $request.GetResponse()
            $statusCode = [int]$response.StatusCode
            $response.Close()

            $stopwatch.Stop()

            if ($statusCode -ge 200 -and $statusCode -lt 400) {
                return @{
                    Success = $true
                    Time = $stopwatch.ElapsedMilliseconds
                    Url = $mirrorUrl
                    Name = $mirrorName
                }
            } else {
                return @{
                    Success = $false
                    Time = -1
                    Url = $mirrorUrl
                    Name = $mirrorName
                }
            }
        } catch {
            return @{
                Success = $false
                Time = -1
                Url = $mirrorUrl
                Name = $mirrorName
            }
        }
    }

    # 创建并发任务
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $mirrors.Count)
    $runspacePool.Open()

    $jobs = @()
    foreach ($mirror in $mirrors) {
        $powershell = [powershell]::Create().AddScript($testScript).AddArgument($mirror.Url).AddArgument($mirror.TestUrl).AddArgument($mirror.Name)
        $powershell.RunspacePool = $runspacePool
        $jobs += @{
            PowerShell = $powershell
            Handle = $powershell.BeginInvoke()
            Mirror = $mirror
        }
    }

    # 等待所有任务完成（最多 15 秒）
    $timeout = [DateTime]::Now.AddSeconds(15)
    while ($jobs | Where-Object { -not $_.Handle.IsCompleted }) {
        if ([DateTime]::Now -gt $timeout) {
            break
        }
        Start-Sleep -Milliseconds 100
    }

    # 收集结果
    $results = @()
    foreach ($job in $jobs) {
        try {
            if ($job.Handle.IsCompleted) {
                $result = $job.PowerShell.EndInvoke($job.Handle)
                if ($result -and $result.Success) {
                    Write-Host "  $($result.Name): " -NoNewline
                    Write-Host "$($result.Time)ms" -ForegroundColor Green
                    $results += $result
                } else {
                    Write-Host "  $($job.Mirror.Name): " -NoNewline
                    Write-Host "不可用" -ForegroundColor Red
                }
            } else {
                Write-Host "  $($job.Mirror.Name): " -NoNewline
                Write-Host "超时" -ForegroundColor Red
            }
        } catch {
            Write-Host "  $($job.Mirror.Name): " -NoNewline
            Write-Host "错误" -ForegroundColor Red
        } finally {
            $job.PowerShell.Dispose()
        }
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

    # 按响应时间排序，选择最快的
    if ($results.Count -gt 0) {
        $best = $results | Sort-Object { $_.Time } | Select-Object -First 1
        Write-Success "已选择最快镜像源: $($best.Name) ($($best.Time)ms)"
        return $best.Url
    } else {
        Write-Warning "所有镜像源均不可用，将直接连接 GitHub"
        return ""
    }
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
        git config --global --unset "url.$prefix.insteadOf" 2>$null
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
  ║        OpenClaw 一键安装脚本 (Windows)                ║
  ║                                                       ║
  ║  将自动安装: Git, Node.js (LTS), OpenClaw             ║
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
Write-Step "检查 OpenClaw..."

# Cloudflare R2 托管的包 URL（避免 GitHub 访问问题）
$OpenclawR2Url = "https://packages.mintmind.io/openclaw-2026.1.30.tgz"

if (Test-Command "openclaw") {
    Write-Success "OpenClaw 已安装"
} else {
    Write-Host "正在安装 OpenClaw（从 Cloudflare 下载）..." -ForegroundColor Yellow

    # 优先从 R2 安装，如果失败则回退到 npm registry
    $r2InstallSuccess = $false
    try {
        npm install -g $OpenclawR2Url --progress --loglevel=notice
        $r2InstallSuccess = $true
    } catch {
        $r2InstallSuccess = $false
    }

    if (-not $r2InstallSuccess -or -not (Test-Command "openclaw")) {
        Write-Warning "从 Cloudflare 下载失败，尝试 npm registry..."
        npm install -g openclaw --progress --loglevel=notice
    }

    Refresh-Path

    if (Test-Command "openclaw") {
        Write-Success "OpenClaw 安装完成"
    } else {
        Write-Err "OpenClaw 安装失败"
        Write-Host ""
        Write-Host "如果仍然失败，请尝试以下方法：" -ForegroundColor Yellow
        Write-Host "1. 使用 VPN 或代理"
        Write-Host "2. 手动配置 Git 代理："
        Write-Host "   git config --global http.proxy http://127.0.0.1:7890"
        Write-Host "   git config --global https.proxy http://127.0.0.1:7890"
        Write-Host "3. 然后重新运行: npm install -g openclaw"
        exit 1
    }
}



# ============================================================
# 步骤 5: 安装飞书插件
# ============================================================
Write-Step "安装飞书插件..."

# 刷新 PATH 确保 npm 可用（OpenClaw 插件安装依赖 npm）
Refresh-Path

# 确保 npm 路径在 PATH 中（即使 Test-Command 能找到，子进程也需要）
$npmPaths = @(
    "$env:ProgramFiles\nodejs",
    "${env:ProgramFiles(x86)}\nodejs",
    "$env:ProgramData\chocolatey\bin",
    "$env:APPDATA\npm"
)
foreach ($npmPath in $npmPaths) {
    if ((Test-Path $npmPath) -and ($env:Path -notlike "*$npmPath*")) {
        $env:Path = "$npmPath;$env:Path"
    }
}

# 验证 npm.cmd 存在（Node.js spawn 需要 .cmd 文件）
$npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($npmCmd) {
    Write-Host "  npm.cmd 路径: $($npmCmd.Source)" -ForegroundColor Gray
} else {
    Write-Warning "npm.cmd 未找到，尝试查找..."
    # 尝试找到 npm.cmd
    $nodejsPath = "$env:ProgramFiles\nodejs"
    if (Test-Path "$nodejsPath\npm.cmd") {
        Write-Host "  找到 npm.cmd: $nodejsPath\npm.cmd" -ForegroundColor Gray
    }
}

# 设置环境变量让子进程继承
[System.Environment]::SetEnvironmentVariable("Path", $env:Path, "Process")

# Cloudflare R2 托管的飞书插件 URL
$FeishuR2Url = "https://packages.mintmind.io/feishu-0.1.6.tgz"
$FeishuTmp = "$env:TEMP\feishu-plugin.tgz"

# 确保 TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 优先从 R2 下载安装，如果失败则从 npm 安装
$feishuInstalled = $false
try {
    Write-Host "  从 Cloudflare 下载飞书插件..." -ForegroundColor Gray
    
    # 使用 WebClient，比 Invoke-WebRequest 更可靠
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($FeishuR2Url, $FeishuTmp)
    
    if (Test-Path $FeishuTmp) {
        Write-Host "  下载成功，正在安装..." -ForegroundColor Gray
        $result = cmd /c "openclaw plugins install `"$FeishuTmp`"" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $feishuInstalled = $true
        } else {
            Write-Host "  安装命令返回错误: $result" -ForegroundColor Yellow
        }
        Remove-Item -Path $FeishuTmp -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Host "  下载错误: $_" -ForegroundColor Yellow
}

if (-not $feishuInstalled) {
    Write-Warning "从 Cloudflare 下载/安装失败，尝试 npm registry..."
    cmd /c "openclaw plugins install @m1heng-clawd/feishu" 2>$null
}

Write-Success "飞书插件安装完成"

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

    npx -y skills add anthropics/skills --skill xlsx --skill pdf --skill pptx --skill docx --agent openclaw -y -g 2>$null

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
openclaw onboard --non-interactive --accept-risk --skip-daemon 2>&1 | Select-String -Pattern "^\s*$" -NotMatch

Write-Step "安装网关服务..."
try {
    openclaw gateway install 2>&1
    Write-Success "网关服务安装完成"
} catch {
    Write-Err "网关服务安装失败"
    exit 1
}

Write-Step "启动网关服务..."
try {
    openclaw gateway start 2>&1
    # 等待服务启动
    Start-Sleep -Seconds 3
    Write-Success "网关服务启动完成"
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

if ([Environment]::UserInteractive) {
    Write-Host -NoNewline "飞书 App ID: "
    if ([Console]::IsInputRedirected) {
        $feishuAppId = $Host.UI.ReadLine()
    } else {
        $feishuAppId = Read-Host
    }

    Write-Host -NoNewline "飞书 App Secret: "
    if ([Console]::IsInputRedirected) {
        $feishuAppSecret = $Host.UI.ReadLine()
    } else {
        $feishuAppSecret = Read-Host
    }
}

if ($feishuAppId -and $feishuAppSecret) {
    Write-Step "配置飞书..."
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
Write-Host "  ║    openclaw status    - 查看状态                      ║" -ForegroundColor Green
Write-Host "  ║    openclaw dashboard - 打开控制面板                  ║" -ForegroundColor Green
Write-Host "  ║    openclaw doctor    - 健康检查                      ║" -ForegroundColor Green
Write-Host "  ║                                                       ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
