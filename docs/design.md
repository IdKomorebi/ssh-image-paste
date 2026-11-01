# 工作原理与边界

## 两个剪贴板与一次按键

远程程序无法直接读取 Windows 剪贴板。热键脚本把一次 Alt+V 分为两步：先上传图片，收到 helper 的成功响应后，再向原窗口发送一次 Alt+V。第二次按键由远程 CLI 原生处理。

PNG 通过 SSH 标准输入传输，不依赖终端文字粘贴协议。Windows 端使用 .NET 标准流的二进制接口，避免把图片当作字符串编码；进程句柄、超时、标准输出/错误均由独立 transport 模块管理。

## X11 selection 是一个服务，不是普通文件

Xvfb 提供无屏幕的 X11 服务；xclip 作为 selection owner 保持 `image/png` 数据。只把文件放到服务器目录，不会自动更新 X11 剪贴板。xclip 子进程与 Xvfb 都关闭继承的 SSH 输入/输出，避免 SSH 一直等不到 EOF。

私有状态位于 `~/.local/state/ssh-image-paste/display-N/`。helper 用 flock 串行化启动/停止，验证 PID 对应的是自己的认证文件，并用 xdpyinfo 探测实际可连接性。它不会通过模糊的进程名匹配接管其他显示号。

Xvfb 关闭 TCP 监听，并使用 MIT-MAGIC-COOKIE-1 认证；客户端通过 XAUTHORITY 读取当前用户私有的 cookie。参考 [X.Org 文档](https://www.x.org/guide/communication/)。它可以阻止未持有 cookie 的 X11 客户端，但不隔离同一个 Linux 用户和 root。

## 环境变量属于进程

env.sh 设置 DISPLAY、XAUTHORITY、PATH 和可选状态目录，并确保显示服务运行。修改文件、重启 H 或在另一个终端执行 export，都不会更新已经运行的 CLI。必须在启动 CLI 的那个 shell 中加载环境，然后重启 CLI。这也是“服务看起来已启动，但程序仍报 unreachable”的常见原因。

## 明确没有做的事

- 不修改远程 CLI 二进制，不依赖反汇编得到的私有实现细节。
- 不自动识别 VS Code 当前连接的主机或终端焦点。
- 不持续截图，不在待机时轮询或保持单独的 SSH 上传连接。
- 不安装 Windows 开机启动项，不依赖 systemd --user。
- 不为每个 CLI 维护独立剪贴板；同一显示号最后写入的图片会被共享。
- 不保证不同 CLI 的原生粘贴快捷键与路径识别行为相同。

## 测试层次

Windows smoke tests 检查脚本语法、全部字节值的传输、带空格/引号/末尾反斜杠的参数和 shell 字面量边界。Linux tests 使用临时前缀、临时状态目录、独立 :199，检查真实 Xvfb/xclip 的图片往返、权限、认证和生命周期。

Windows → SSH → Linux 的端到端测试额外比较实际发送 PNG 与远程读回 PNG 的 SHA-256。上述检查不等于对所有 CLI UI 做了端到端测试；实际输入框的附件显示由对应 CLI 版本验证。
