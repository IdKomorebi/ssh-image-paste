$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $root 'windows') -Recurse -File | Where-Object { $_.Extension -in '.ps1','.psm1' })) {
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
}
Import-Module (Join-Path $root 'windows/lib/Transport.psm1') -Force
$temporary = Join-Path $env:TEMP ('ssh-image-paste-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
try {
    $inputPath = Join-Path $temporary 'all bytes.bin'
    $outputPath = Join-Path $temporary 'read back.bin'
    [IO.File]::WriteAllBytes($inputPath, [byte[]]((0..255) * 256))
    $powershellPath = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powershellPath)) { $powershellPath = Join-Path $PSHOME 'pwsh.exe' }
    # Use a native console fixture, not a PowerShell text host, as the byte echo endpoint.
    $echoSource = Join-Path $temporary 'BinaryEcho.cs'
    $echoBinary = Join-Path $temporary 'BinaryEcho.exe'
    [IO.File]::WriteAllText($echoSource, 'using System; class BinaryEcho { static void Main(string[] args) { Console.OpenStandardInput().CopyTo(Console.OpenStandardOutput()); } }')
    $compiler = Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $compiler /nologo /target:exe ('/out:' + $echoBinary) $echoSource
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile native binary echo fixture.' }
    $originalEncoding = [Console]::InputEncoding
    try {
        foreach ($encoding in @($originalEncoding, [Text.UTF8Encoding]::new($true))) {
            [Console]::InputEncoding = $encoding
            $result = Invoke-BinaryProcess -FilePath $echoBinary -Arguments @('unused') -InputFile $inputPath -OutputFile $outputPath
            if ($result.ExitCode -ne 0) { throw ('Binary echo failed: ' + $result.StdErr) }
            if ((Get-FileHash -LiteralPath $inputPath).Hash -ne (Get-FileHash -LiteralPath $outputPath).Hash) {
                throw ('Binary transport changed bytes (sent={0}, received={1}, preamble={2}).' -f (Get-Item -LiteralPath $inputPath).Length, (Get-Item -LiteralPath $outputPath).Length, $encoding.GetPreamble().Length)
            }
            if ([Console]::InputEncoding.GetPreamble().Length -ne $encoding.GetPreamble().Length) { throw 'Transport changed caller console encoding.' }
        }
    } finally {
        [Console]::InputEncoding = $originalEncoding
    }
    if ((ConvertTo-NativeArgument '') -cne '""') { throw 'Empty native argument quoting failed.' }
    $values = @('two words', 'quote"inside', 'C:\a path\', 'apostrophe''s', ('Unicode-' + [char]0x56fe + [char]0x7247))
    $echoScript = '[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false); $args | ConvertTo-Json -Compress'
    # A real script file makes PowerShell preserve argument boundaries after -File.
    $echoPath = Join-Path $temporary 'echo arguments.ps1'
    [IO.File]::WriteAllText($echoPath, $echoScript, [Text.UTF8Encoding]::new($true))
    $result = Invoke-BinaryProcess -FilePath $powershellPath -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$echoPath) + $values)
    if ($result.ExitCode -ne 0) { throw ('Argument echo failed: ' + $result.StdErr) }
    $actual = $result.StdOut | ConvertFrom-Json
    if ($actual.Count -ne $values.Count) { throw 'Argument count changed.' }
    for ($index = 0; $index -lt $values.Count; $index++) {
        if ($actual[$index] -cne $values[$index]) { throw ('Argument changed at index ' + $index) }
    }
    $command = Get-RemoteCommand -Helper "~/some dir/apostrophe's.sh" -Display ':199' -Action put
    if (-not $command.Contains("'\''")) { throw 'Shell apostrophe quoting is missing.' }
    $rejected = $false
    try { Get-RemoteCommand -Helper '~/helper' -Display ':99; touch /tmp/should-not-exist' -Action put | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unsafe display was accepted.' }
    $timedOut = $false
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try { Invoke-BinaryProcess -FilePath $powershellPath -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 30') -TimeoutSeconds 1 | Out-Null } catch { $timedOut = $_.Exception.Message -match 'timed out' }
    if (-not $timedOut -or $stopwatch.Elapsed.TotalSeconds -gt 8) { throw 'Timeout did not stop the child promptly.' }
    Write-Host 'PASS: PowerShell syntax, binary transport including UTF-8 BOM consoles, native/Unicode argument boundaries, shell quoting, display validation, timeout.'
} finally {
    # Only the freshly created, uniquely named test directory is removed.
    $resolved = [IO.Path]::GetFullPath($temporary)
    $expectedParent = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected temporary directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
