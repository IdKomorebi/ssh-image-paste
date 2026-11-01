# Contributing

Small fixes and reproducible bug reports are welcome. Include Windows/PowerShell/AutoHotkey versions, Linux distribution, CLI version and its native paste shortcut, selected display number, and redacted errors. Do not post SSH keys, private screenshots, or unredacted server configuration.

Before submitting changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-smoke.ps1
```

```bash
bash tests/server-smoke.sh
```

Server tests need a free :199 and use only a temporary prefix/state directory. Add tests for actual failure modes: binary corruption, shell/native argument boundaries, authentication, display collisions, or stuck SSH streams. Keep machine-specific configuration in ignored `windows/config.ini`.
