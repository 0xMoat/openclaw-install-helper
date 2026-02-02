# OpenClaw飞书版 一键安装脚本

欢迎使用！这个工具可以帮你在电脑上一键安装 OpenClaw 数字员工，并自动连接到你的飞书机器人。

无需懂代码，只需复制一行命令即可完成配置。

## 🚀 如何安装

### ✅ Windows 用户

1.  在电脑左下角搜索 **"PowerShell"**。
2.  在图标上点击 **右键**，选择 **「以管理员身份运行」**。
3.  复制下面的命令，粘贴到窗口中，然后按 **回车键**：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ([Text.Encoding]::UTF8.GetString((iwr 'https://cdn.jsdelivr.net/gh/0xMoat/openclaw-install-helper@main/install.ps1' -UseBasicParsing).Content))
```

> 安装过程中可能会弹出提示框，请全部选择「允许」或「是」。

---

### 🍎 macOS 用户

1.  按 `Command + 空格`，搜索 **"终端"** (Terminal) 并打开。
2.  复制下面的命令，粘贴到窗口中，然后按 **回车键**：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/0xMoat/openclaw-install-helper@main/install.sh | bash
```

> 如果提示需要密码，请输入你的电脑开机密码（输入时不会显示字符），然后按回车。

---

## ❓ 常见问题

**Q: 安装需要多久？**
A: 取决于你的网速，通常需要 3-5 分钟。

**Q: Windows 提示“执行策略更改”？**
A: 请在命令前输入 `A` 然后按回车（代表 Yes to All）。

**Q: 安装失败怎么办？**
A:
1.  检查网络连接是否正常。
2.  Windows 用户请确保你是以**管理员身份**运行的 PowerShell。
3.  关闭杀毒软件后重试（有时会误报）。
4.  如果还不行，请联系技术支持，并提供报错截图。

**Q: 安装完成后怎么用？**
A: 安装成功后，你会看到绿色的成功提示。此时你的飞书机器人应该已经上线了！你也可以在浏览器打开 `http://127.0.0.1:18789` 查看后台。
