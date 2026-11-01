# 故障排查

## X11 server unreachable / clipboard unavailable

分清“服务器显示服务没启动”和“CLI 环境变量不对”。在**启动 CLI 的同一个远程终端**运行：

```bash
source ~/.config/ssh-image-paste/env.sh
printf 'DISPLAY=%s\nXAUTHORITY=%s\n' "$DISPLAY" "$XAUTHORITY"
timeout 3 xdpyinfo >/dev/null && echo X11_OK
~/.local/bin/ssh-image-paste-server --display :99 status
```

1. `DISPLAY` 应与 Windows config.ini 的 Display 相同。
2. `XAUTHORITY` 应指向安装器生成的当前用户认证文件，不能沿用其他 X11 转发会话的文件。
3. `xdpyinfo` 成功但 CLI 仍报错：退出 CLI，加载环境后重新启动。
4. tmux 中的旧 shell、VS Code 已存在的终端，不会因为后来修改 `.bashrc` 自动更新。
5. 如果终端还设置了不可用的 `WAYLAND_DISPLAY`，有些 CLI 会优先尝试 Wayland。可只为本次 CLI 启动移除它，例如 `env -u WAYLAND_DISPLAY codex`；不要修改其他桌面会话的环境。

## Xvfb 已被占用 / stale socket

本项目只管理 PID 文件与认证文件均匹配的 Xvfb。发现其他程序使用 `:99` 时会拒绝接管。选择 `:100` 等空闲显示号重新安装，再修改 Windows 配置并重启 CLI。

不要仅凭 `pgrep -f 'Xvfb :99'` 判断健康：它可能匹配包含这段文字的父 shell/SSH 命令。不要直接删除其他用户的 `/tmp/.X11-unix` socket 或 `.X*-lock`。

## SSH 失败、密码提示、未知服务器指纹

先在本地 PowerShell 执行：

```powershell
ssh myserver "echo ok"
ssh -o BatchMode=yes -o ClearAllForwardings=yes myserver "echo ok"
```

手动完成指纹确认并配置密钥；若使用有口令的私钥，确保本机 ssh-agent 已解锁。脚本不会绕过指纹检查或在后台输入密码。端口、跳板机、密钥文件等都由你的 SSH config 决定。

图片上传连接显式关闭端口转发，避免重复申请 VS Code 连接已经使用的 RemoteForward 端口。

## 找不到 xclip / helper

非交互 SSH 不一定加载 `.bashrc`。helper 自己把其安装目录及 `~/.local/bin` 加入 PATH。默认 helper 为 `~/.local/bin/ssh-image-paste-server`；如果安装到其他位置，修改 config.ini 的 RemoteHelper。

若出现共享库 `not found`，仅复制 xclip 二进制不能补齐系统库，请管理员安装依赖。

## H 图标没出现

确认安装的是 AutoHotkey **v2**，不是 v1；检查隐藏托盘图标区。直接运行 `windows/paste-image.ahk` 可看到配置错误提示。

检查 `windows/config.ini` 是否存在，以及 HostName、Display、Mode 是否有效。`.ahk` 是脚本，运行它的 EXE 是已安装的 AutoHotkey64.exe。

## Alt+V 没反应 / 打开了菜单

- 正式版 VS Code 默认进程名是 `Code.exe`；Insiders 必须更改 AppExe。
- 剪贴板必须真有图片。复制图片文件和复制图片像素不是一回事；先用 `Win+Shift+S` 测试。
- 请聚焦远程 CLI 的输入框，不能停在编辑器、命令面板或本地 shell。
- 配置中的 HostName 是固定上传目标，和当前 VS Code 连接必须一致。
- 图片已上传但 CLI 没附件：确认它的该版本支持原生 Alt+V X11 贴图，检查 CLI 环境；其他工具可能使用不同快捷键。
- Alt+V 与 Ctrl+V 的行为由终端/CLI共同决定。本项目没有修改 VS Code 或 Windows Terminal 的 Ctrl+V 绑定。

## path 模式只出现文字路径

这不一定是上传失败。路径已经保存，但附件识别依赖 CLI 和 bracketed paste。默认 clipboard 模式直接使用远程图片剪贴板，避免把“敲入路径”和“附加图片”等同起来。

## 日志与错误码

Windows 日志：`%LOCALAPPDATA%\ssh-image-paste\paste-image.log`。

| PowerShell 退出码 | 含义 |
|---|---|
| 0 | 远程 helper 已确认上传成功 |
| 2 | 本机剪贴板没有图片 |
| 3 | SSH / 远程 helper 返回失败 |
| 4 | 本地读取、超时、依赖或响应校验失败 |

日志不记录图片内容。提交 issue 前仍应移除日志中的个人主机名、IP、用户名，不要附上 SSH 私钥或真实敏感截图。

## 从早期手工 Xvfb :99 方案迁移

早期方案可能只有 `export DISPLAY=:99`，没有认证文件，也没有本项目的 PID 状态。公开版不会接管它。最简单的迁移方式是为本项目选择新的空闲显示号，加载新生成的 env.sh，并在 Windows 配置中使用新显示号。旧服务确认不再使用后，再由你自行停止。
