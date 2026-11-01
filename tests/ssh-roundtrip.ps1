# Uses only a generated fixture, never reads or changes the Windows clipboard.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.@-]*$')][string]$HostName,
    [ValidatePattern('^:[0-9]+$')][string]$Display = ':199',
    [string]$RemoteHelper = '~/.local/bin/ssh-image-paste-server'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'windows/lib/Transport.psm1') -Force
Add-Type -AssemblyName System.Drawing
$temporary = Join-Path $env:TEMP ('ssh-image-paste-roundtrip-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
try {
    $fixturePath = Join-Path $temporary 'fixture.png'
    $expectedPath = Join-Path $temporary 'encoded.png'
    $downloadPath = Join-Path $temporary 'read-back.png'
    $bitmap = New-Object Drawing.Bitmap(8,8)
    try {
        for ($x = 0; $x -lt 8; $x++) {
            for ($y = 0; $y -lt 8; $y++) { $bitmap.SetPixel($x, $y, [Drawing.Color]::FromArgb(255, $x * 30, $y * 30, 128)) }
        }
        $bitmap.Save($fixturePath, [Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
    # Match the upload program's PNG encoding, rather than comparing two different encodings of the same pixels.
    $image = [Drawing.Image]::FromFile($fixturePath)
    try { $image.Save($expectedPath, [Drawing.Imaging.ImageFormat]::Png) } finally { $image.Dispose() }
    & (Join-Path $root 'windows/paste-image.ps1') -HostName $HostName -Display $Display -RemoteHelper $RemoteHelper -ImagePath $fixturePath
    if ($LASTEXITCODE -ne 0) { throw ('Upload exited with ' + $LASTEXITCODE) }
    $command = Get-RemoteCommand -Helper $RemoteHelper -Display $Display -Action get
    $arguments = @('-T','-x','-o','BatchMode=yes','-o','ConnectTimeout=5','-o','ClearAllForwardings=yes','-o','StrictHostKeyChecking=yes',$HostName,$command)
    $result = Invoke-BinaryProcess -FilePath (Get-Command ssh.exe).Source -Arguments $arguments -OutputFile $downloadPath
    if ($result.ExitCode -ne 0) { throw ('Read-back failed: ' + $result.StdErr) }
    $expectedHash = (Get-FileHash -LiteralPath $expectedPath).Hash
    $actualHash = (Get-FileHash -LiteralPath $downloadPath).Hash
    if ($expectedHash -ne $actualHash) { throw 'SSH clipboard round trip changed the encoded PNG bytes.' }
    $decoded = [Drawing.Bitmap]::FromFile($downloadPath)
    try {
        if ($decoded.Width -ne 8 -or $decoded.Height -ne 8) { throw 'Decoded image dimensions changed.' }
        for ($x = 0; $x -lt 8; $x++) {
            for ($y = 0; $y -lt 8; $y++) {
                if ($decoded.GetPixel($x,$y).ToArgb() -ne [Drawing.Color]::FromArgb(255, $x * 30, $y * 30, 128).ToArgb()) { throw 'Decoded image pixels changed.' }
            }
        }
    } finally { $decoded.Dispose() }
    Write-Host ('PASS: Windows -> SSH -> X11 -> SSH PNG SHA-256 ' + $actualHash)
    Write-Host 'PASS: decoded dimensions and every pixel match the generated fixture.'
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    $expectedParent = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected temporary directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
