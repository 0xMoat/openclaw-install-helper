# GitHub 代理 - Cloudflare Worker

当所有公共 GitHub 镜像源都不可用时，你可以使用 Cloudflare Workers 免费部署自己的代理。

## 部署步骤

### 1. 创建 Cloudflare 账号
访问 [Cloudflare](https://dash.cloudflare.com/sign-up) 注册（免费）

### 2. 创建 Worker
1. 登录后进入 **Workers & Pages**
2. 点击 **Create application** → **Create Worker**
3. 给 Worker 起个名字（如 `gh-proxy`）
4. 点击 **Deploy**

### 3. 编辑代码
1. 部署后点击 **Edit code**
2. 删除默认代码，粘贴 `github-proxy.js` 的内容
3. 点击 **Save and Deploy**

### 4. 获取你的代理地址
部署完成后，你会得到一个地址，格式如：
```
https://gh-proxy.your-name.workers.dev
```

## 使用方法

### 方法 1：设置环境变量（推荐）

**Windows PowerShell:**
```powershell
$env:GITHUB_MIRROR = "https://gh-proxy.your-name.workers.dev/https://github.com/"
irm https://install.openclaw.io/install.ps1 | iex
```

**macOS/Linux:**
```bash
export GITHUB_MIRROR="https://gh-proxy.your-name.workers.dev/https://github.com/"
curl -fsSL https://install.openclaw.io/install.sh | bash
```

### 方法 2：手动配置 Git

```bash
git config --global url."https://gh-proxy.your-name.workers.dev/https://github.com/".insteadOf "https://github.com/"
git config --global url."https://gh-proxy.your-name.workers.dev/https://github.com/".insteadOf "ssh://git@github.com/"
git config --global url."https://gh-proxy.your-name.workers.dev/https://github.com/".insteadOf "git@github.com:"
```

安装完成后清除配置：
```bash
git config --global --unset-all url.https://gh-proxy.your-name.workers.dev/https://github.com/.insteadOf
```

## 免费额度

Cloudflare Workers 免费版提供：
- 每天 100,000 次请求
- 完全足够个人使用

## 注意事项

- 代理仅支持 GitHub 相关域名
- 不要分享你的 Worker 地址，避免被滥用
