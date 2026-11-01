# Windows PowerShell 5.1 / PowerShell 7, launched in STA mode by AutoHotkey.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.@-]*$')][string]$HostName,
    [ValidateSet('clipboard','path')][string]$Mode = 'clipboard',
    [string]$Display = ':99',
    [string]$RemoteHelper = '~/.local/bin/ssh-image-paste-server',
    [string]$OutFile,
    [string]$ImagePath
)
$ErrorActionPreference = 'Stop'
$logDirectory = Join-Path $env:LOCALAPPDATA 'ssh-image-paste'
$null = New-Item -ItemType Directory -Path $logDirectory -Force
$logFile = Join-Path $logDirectory 'paste-image.log'
function Write-Log([string]$Message) {
    ('{0:s} [{1}] {2}' -f (Get-Date), $Mode, $Message) | Out-File -LiteralPath $logFile -Append -Encoding utf8
}
$temporary = Join-Path $env:TEMP ('ssh-image-paste-' + [guid]::NewGuid().ToString('N') + '.png')
$image = $null
try {
    Import-Module (Join-Path $PSScriptRoot 'lib/Transport.psm1') -Force
    Add-Type -AssemblyName System.Drawing
    if ($ImagePath) {
        $image = [Drawing.Image]::FromFile((Resolve-Path -LiteralPath $ImagePath).Path)
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        if (-not [Windows.Forms.Clipboard]::ContainsImage()) { Write-Log 'Clipboard has no image.'; exit 2 }
        $image = [Windows.Forms.Clipboard]::GetImage()
    }
    if ($null -eq $image) { throw 'Could not read clipboard bitmap.' }
    $image.Save($temporary, [Drawing.Imaging.ImageFormat]::Png)
    $image.Dispose()
    $image = $null
    if ((Get-Item -LiteralPath $temporary).Length -gt 64MB) { throw 'PNG exceeds the 64 MiB limit.' }
    $action = if ($Mode -eq 'clipboard') { 'put' } else { 'save' }
    $remoteCommand = Get-RemoteCommand -Helper $RemoteHelper -Display $Display -Action $action
    $sshPath = (Get-Command ssh.exe -ErrorAction Stop).Source
    $sshArguments = @('-T','-x','-o','BatchMode=yes','-o','ConnectTimeout=5',
        '-o','ClearAllForwardings=yes','-o','StrictHostKeyChecking=yes',
        '-o','ServerAliveInterval=5','-o','ServerAliveCountMax=2',$HostName,$remoteCommand)
    $result = Invoke-BinaryProcess -FilePath $sshPath -Arguments $sshArguments -InputFile $temporary
    if ($result.ExitCode -ne 0) {
        Write-Log ('SSH exit {0}: {1}' -f $result.ExitCode, $result.StdErr.Trim())
        exit 3
    }
    $answer = $result.StdOut.Trim()
    if ($Mode -eq 'clipboard' -and $answer -ne 'OK') { throw ('Unexpected remote response: ' + $answer) }
    if ($Mode -eq 'path' -and ($answer -notmatch '^/' -or $answer -match '[\r\n]')) { throw 'Remote helper did not return one absolute file path.' }
    if ($OutFile) { [IO.File]::WriteAllText($OutFile, $answer, [Text.UTF8Encoding]::new($false)) }
    Write-Log 'Upload completed.'
    exit 0
} catch {
    Write-Log ('Error: ' + $_.Exception.Message)
    exit 4
} finally {
    if ($image) { $image.Dispose() }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
