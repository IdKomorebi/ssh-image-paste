[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.@-]*$')][string]$HostName,
    [ValidatePattern('^:[0-9]+$')][string]$Display = ':99',
    [ValidateSet('clipboard','path')][string]$Mode = 'clipboard',
    [string]$RemoteHelper = '~/.local/bin/ssh-image-paste-server',
    [string]$AppExe = 'Code.exe',
    [string]$AutoHotkeyPath,
    [switch]$NoDesktopShortcut,
    [switch]$SkipSshCheck,
    [switch]$Start,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
if ($RemoteHelper -match '[\r\n"]' -or $AppExe -notmatch '^[A-Za-z0-9 ._-]+\.exe$') { throw 'Invalid helper path or AppExe.' }
if (-not $AutoHotkeyPath) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe')
    )
    $AutoHotkeyPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $AutoHotkeyPath -or -not (Test-Path -LiteralPath $AutoHotkeyPath)) {
    throw 'Install AutoHotkey v2 first: winget install --id AutoHotkey.AutoHotkey --exact'
}
if ((Get-Item -LiteralPath $AutoHotkeyPath).VersionInfo.FileMajorPart -ne 2) { throw 'AutoHotkey v2 is required.' }
$configPath = Join-Path $PSScriptRoot 'config.ini'
if ((Test-Path -LiteralPath $configPath) -and -not $Force) { throw 'config.ini already exists. Use -Force to replace it intentionally.' }
if (-not $SkipSshCheck) {
    & ssh.exe -T -x -o BatchMode=yes -o ConnectTimeout=8 -o ClearAllForwardings=yes -o StrictHostKeyChecking=yes $HostName 'printf SSH_IMAGE_PASTE_OK'
    if ($LASTEXITCODE -ne 0) { throw 'Passwordless SSH failed. Connect once manually to verify the host key, then fix SSH keys/config.' }
}
if ($PSCmdlet.ShouldProcess($configPath, 'Create personal configuration')) {
    $config = @"
[ssh-image-paste]
HostName=$HostName
Mode=$Mode
Display=$Display
RemoteHelper=$RemoteHelper
AppExe=$AppExe
"@
    [IO.File]::WriteAllText($configPath, $config, [Text.Encoding]::Unicode)
}
$scriptPath = Join-Path $PSScriptRoot 'paste-image.ahk'
if (-not $NoDesktopShortcut -and $PSCmdlet.ShouldProcess('Desktop', 'Create SSH Image Paste shortcut')) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'SSH Image Paste.lnk'))
    $shortcut.TargetPath = $AutoHotkeyPath
    $shortcut.Arguments = '"' + $scriptPath + '"'
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.IconLocation = $AutoHotkeyPath + ',0'
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Windows screenshot to remote SSH CLI: Alt+V'
    $shortcut.Save()
}
if ($Start -and $PSCmdlet.ShouldProcess($scriptPath, 'Start background hotkey')) {
    Start-Process -FilePath $AutoHotkeyPath -ArgumentList ('"' + $scriptPath + '"') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
}
Write-Host 'Configured. Start the desktop shortcut (H tray icon), then use Alt+V in the target VS Code CLI input.'
Write-Host 'On the server, source ~/.config/ssh-image-paste/env.sh BEFORE restarting the CLI.'
