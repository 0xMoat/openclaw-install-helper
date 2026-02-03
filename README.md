# OpenClaw飞书版 一键安装脚本

欢迎使用！这个工具可以帮你在电脑上一键安装 OpenClaw 数字员工，并自动连接到你的飞书机器人。

无需懂代码，只需复制一行命令即可完成配置。

## 🚀 安装流程

### 步骤一：在飞书开放平台创建应用

1. 前往 [飞书开放平台](https://open.feishu.cn) 进入开发者后台
2. 点击「创建你的应用」
3. 为应用取名后创建
4. 为应用添加「机器人」能力
5. 进入「权限管理」，点击「批量开通」
6. 复制以下 JSON 并粘贴后确认：

```json
{
  "scopes": {
    "tenant": [
      "contact:contact.base:readonly",
      "im:message",
      "im:message.p2p_msg:readonly",
      "im:message.group_at_msg:readonly",
      "im:message:send_as_bot",
      "im:resource",
      "contact:user.base:readonly",
      "im:message.group_msg",
      "im:message:readonly",
      "im:message:update",
      "im:message:recall",
      "im:message.reactions:read",
      "docx:document:readonly",
      "drive:drive:readonly",
      "wiki:wiki:readonly",
      "bitable:app:readonly",
      "docx:document",
      "docx:document.block:convert",
      "drive:drive",
      "wiki:wiki",
      "bitable:app"
    ]
  }
}
```

7. 点击「版本管理与发布」→「创建版本」
8. 填写版本号（如 1.0.0）和说明，滚动到页面底部保存发布
9. 回到「凭证与基础信息」，复制 **App ID** 和 **App Secret**

---

### 步骤二：运行安装脚本

#### 🍎 macOS 用户

1. 按 `Command + 空格`，搜索 **"终端"** (Terminal) 并打开
2. 复制下面的命令，粘贴到窗口中，然后按 **回车键**：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/0xMoat/openclaw-install-helper@main/install.sh | bash
```

> 如果提示需要密码，请输入你的电脑开机密码（输入时不会显示字符），然后按回车。

---

#### ✅ Windows 用户

1. 在电脑左下角搜索 **"PowerShell"**
2. 在图标上点击 **右键**，选择 **「以管理员身份运行」**
3. 复制下面的命令，粘贴到窗口中，然后按 **回车键**：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; $ProgressPreference='SilentlyContinue'; iex ([Text.Encoding]::UTF8.GetString((iwr 'https://cdn.jsdelivr.net/gh/0xMoat/openclaw-install-helper@main/install.ps1' -UseBasicParsing).Content))
```

> 安装过程中可能会弹出提示框，请全部选择「允许」或「是」。

---

### 步骤三：输入凭证

脚本运行过程中会提示输入 **App ID** 和 **App Secret**（步骤一获取的）

---

### 步骤四：千问授权

1. 脚本会自动打开浏览器，登录或注册千问账号
2. 登录后点击「确认授权」

---

### 步骤五：完成飞书配置

脚本安装完成后，回到飞书开放平台：

1. 进入「事件与回调」→「事件配置」，开启「长连接」模式
2. 点击「添加事件」→ 勾选「接收消息」
3. 再次进入「版本管理与发布」→「创建版本」
4. 填写新版本号（如 2.0.0）和说明，保存发布
5. 打开飞书消息，找到「开发者小助手」，打开你的应用开始聊天使用！

---

## ❓ 常见问题

**Q: 安装需要多久？**
A: 取决于你的网速，通常需要 3-5 分钟。

**Q: Windows 提示"执行策略更改"？**
A: 请输入 `A` 然后按回车（代表 Yes to All）。

**Q: 安装失败怎么办？**
A:
1. 检查网络连接是否正常
2. Windows 用户请确保以**管理员身份**运行 PowerShell
3. 关闭杀毒软件后重试（有时会误报）
4. 如果还不行，请联系技术支持，并提供报错截图

**Q: 安装完成后怎么用？**
A: 安装成功后会自动打开浏览器显示控制台。你也可以随时运行 `openclaw dashboard` 打开控制台。

**Q: 如何重新授权千问？**
A: 运行以下命令：
```bash
openclaw models auth login --provider qwen-portal --set-default
```
