# SSH Image Paste

**Paste a Windows screenshot into a Linux CLI over SSH, using the CLI's native image attachment feature.**

[中文](README.md) · [Troubleshooting (中文)](docs/troubleshooting.md) · [MIT License](LICENSE)

Take a screenshot with `Win+Shift+S`, focus your remote CLI in VS Code Remote-SSH, and press **Alt+V**. AutoHotkey uploads the PNG through a separate SSH connection, places it in a private Xvfb/xclip clipboard on the server, and forwards Alt+V to the CLI after the upload succeeds.

## Why?

The Windows clipboard and the server clipboard are different. Pasting text into a terminal does not transfer bitmap data to a headless Linux host. A remote CLI may report `clipboard unavailable` or an unreachable X11 server.

This bridge provides the missing remote clipboard. No server desktop, VNC, X11 network forwarding, or user systemd session is required.

## Requirements

- Windows 10/11, Windows PowerShell 5.1, OpenSSH client, AutoHotkey **v2**.
- VS Code stable by default; set `AppExe=Code - Insiders.exe` for Insiders.
- Linux with Bash, Xvfb, xclip, xauth, xdpyinfo, timeout, flock, and openssl.
- A CLI version supporting **native Alt+V image paste from X11**. Different tools/versions use different shortcuts; this is not a claim of universal Codex/agy/Claude compatibility.
- A known SSH host alias with working non-interactive key authentication.

## Install on the Linux server

```bash
git clone https://github.com/IdKomorebi/ssh-image-paste.git
cd ssh-image-paste
# Debian/Ubuntu, if dependencies are not already available:
sudo apt-get install xvfb xclip xauth x11-utils util-linux openssl coreutils
bash server/setup.sh --display :99 --configure-shell
source ~/.config/ssh-image-paste/env.sh
~/.local/bin/ssh-image-paste-server --display :99 self-test
```

`self-test` replaces that display's clipboard with a fixture and checks exact PNG bytes. The installer backs up `.bashrc` before adding an environment source line. Omit `--configure-shell` to leave `.bashrc` untouched.

If only xclip is missing, `--user-xclip` downloads and extracts it from your configured Debian/Ubuntu apt repository without sudo. Its shared libraries and all other dependencies must already exist. Missing Xvfb/libraries still require administrator assistance. Third-party binaries are not bundled.

The service uses a private Xauthority cookie and `-nolisten tcp`. It refuses to adopt an unrelated existing display. If `:99` is occupied, choose another free number and use that number on both ends.

## Install on Windows

Create your own `%USERPROFILE%\.ssh\config` host alias and verify `ssh myserver "echo ok"` works without a password. Confirm the server fingerprint manually on the first connection.

```powershell
git clone https://github.com/IdKomorebi/ssh-image-paste.git
cd ssh-image-paste
winget install --id AutoHotkey.AutoHotkey --exact
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1 -HostName myserver -Display :99 -Start
```

The installer writes ignored `windows/config.ini`, creates a **SSH Image Paste** desktop shortcut, and optionally starts the hotkey. There is no main window: look for the **H** tray icon. Double-clicking again replaces the existing instance. Start the shortcut again after reboot; startup registration is not enabled.

The shortcut runs `AutoHotkey64.exe` with the `.ahk` script. A separately compiled executable is unnecessary. The execution policy flag is process-scoped; system policy is not changed.

## Load the environment BEFORE starting the remote CLI

In the actual VS Code Remote-SSH terminal:

```bash
source ~/.config/ssh-image-paste/env.sh
printf 'DISPLAY=%s\nXAUTHORITY=%s\n' "$DISPLAY" "$XAUTHORITY"
# Start your CLI here.
```

**Exit and restart an already-running CLI after loading the environment.** Existing processes and old tmux terminals do not automatically inherit later changes. Restarting the Windows hotkey cannot fix the remote process environment.

Take a screenshot, focus the remote CLI input, and press **Alt+V**. Confirm that an image attachment appears before submitting your prompt. You may connect SSH before or after starting the hotkey.

## Configuration and boundaries

See [windows/config.example.ini](windows/config.example.ini). `clipboard` is the default. Optional `path` mode saves a private server-side PNG, replaces the local clipboard with its path, and sends Ctrl+V. Whether that path becomes an attachment depends on the terminal/CLI's bracketed-paste behavior.

One hotkey configuration targets one fixed host; it does not detect which server is connected in the active VS Code window. It is scoped to the configured VS Code **window**, not specifically the terminal control. Use it in the correct CLI input. Switching windows during upload prevents automatic key forwarding.

No polling or continuous screen capture occurs. Temporary transfer PNGs are removed. The last remote clipboard image remains available until replaced or the display is stopped; path-mode images remain in `~/.cache/ssh-image-paste/images/`. CLIs sharing one display share the last image. The private X11 cookie does not isolate programs running as the same Linux user.

## Diagnostics

```bash
~/.local/bin/ssh-image-paste-server --display :99 status
~/.local/bin/ssh-image-paste-server --display :99 ensure
~/.local/bin/ssh-image-paste-server --display :99 stop
```

Windows log: `%LOCALAPPDATA%\ssh-image-paste\paste-image.log`.
Server log: `~/.local/state/ssh-image-paste/display-99/Xvfb.log`.
Exit the hotkey from the tray menu. No systemd service is installed; sourcing the environment or the next upload starts the managed display when necessary.

## Tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-smoke.ps1
```

```bash
# Requires dependencies and a free :199. Does not edit .bashrc.
bash tests/server-smoke.sh
```

Tests cover binary transport, quoting, installation, concurrency, exact PNG round trips, invalid input, permissions, X11 authentication, display collision refusal, and restart. GitHub Actions runs the same tests. Native attachment UI behavior remains CLI/version-specific and requires an interactive check.

After installing the server helper, run the optional end-to-end test on a free test display:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\ssh-roundtrip.ps1 -HostName myserver -Display :199
```

It generates a fixture without reading your Windows clipboard, replaces the selected test display's clipboard, compares PNG SHA-256, and verifies every decoded pixel. Stop the test display with `ssh-image-paste-server --display :199 stop` afterward.

## Uninstall

Exit H and remove the Windows shortcut/project. On Linux stop the managed display, remove the source line added to `.bashrc`, then remove the helper and this project's config/state/cache directories as needed. Never remove sockets or locks belonging to unrelated X11 services.

MIT-licensed scripts. AutoHotkey, Xvfb, and xclip are independent dependencies under their own licenses. See the [X.Org authentication documentation](https://www.x.org/guide/communication/) for the cookie mechanism.
