Set-StrictMode -Version Latest

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function ConvertTo-ShellLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function Get-RemoteCommand {
    param([string]$Helper, [string]$Display, [ValidateSet('put','save','get')][string]$Action)
    if ($Display -notmatch '^:[0-9]+$') { throw 'Display must look like :99.' }
    if ([string]::IsNullOrWhiteSpace($Helper) -or $Helper -match '[\r\n]') { throw 'Invalid remote helper path.' }
    $remotePath = if ($Helper.StartsWith('~/')) {
        '"$HOME"/' + (ConvertTo-ShellLiteral $Helper.Substring(2))
    } else { ConvertTo-ShellLiteral $Helper }
    return 'exec bash ' + $remotePath + ' --display ' + (ConvertTo-ShellLiteral $Display) + ' ' + $Action
}

function Invoke-BinaryProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments,
        [string]$InputFile,
        [string]$OutputFile,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 25
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $output = New-Object System.IO.MemoryStream
    $inputStream = $null
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $noBom = [Text.UTF8Encoding]::new($false)
        if ($null -ne $info.PSObject.Properties['StandardInputEncoding']) {
            $info.StandardInputEncoding = $noBom
            $started = $process.Start()
        } else {
            # .NET Framework creates an autoflushing StreamWriter during Start().
            # A UTF-8 console can therefore prepend a BOM even when we write only BaseStream.
            $previousEncoding = [Console]::InputEncoding
            try {
                [Console]::InputEncoding = $noBom
                $started = $process.Start()
            } finally {
                [Console]::InputEncoding = $previousEncoding
            }
        }
        if (-not $started) { throw 'Could not start child process.' }
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($output)
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if ($InputFile) {
            $inputStream = [IO.File]::OpenRead($InputFile)
            $copyTask = $inputStream.CopyToAsync($process.StandardInput.BaseStream)
            if (-not $copyTask.Wait($TimeoutSeconds * 1000)) { throw 'Input transfer timed out.' }
        }
        $process.StandardInput.BaseStream.Close()
        $remaining = [math]::Max(1, $TimeoutSeconds * 1000 - [int]$timer.Elapsed.TotalMilliseconds)
        if (-not $process.WaitForExit($remaining)) { throw 'SSH process timed out.' }
        if (-not $stdoutTask.Wait(2000) -or -not $stderrTask.Wait(2000)) {
            throw 'Child output streams did not close; a remote child may still hold the SSH session.'
        }
        $bytes = $output.ToArray()
        if ($OutputFile) { [IO.File]::WriteAllBytes($OutputFile, $bytes) }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = [Text.Encoding]::UTF8.GetString($bytes)
            StdErr = $stderrTask.Result
        }
    } finally {
        if ($inputStream) { $inputStream.Dispose() }
        try { if (-not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(2000) } } catch {}
        $output.Dispose()
        $process.Dispose()
    }
}

Export-ModuleMember -Function ConvertTo-NativeArgument,ConvertTo-ShellLiteral,Get-RemoteCommand,Invoke-BinaryProcess
