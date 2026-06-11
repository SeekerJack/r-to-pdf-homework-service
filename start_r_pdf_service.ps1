param(
    [switch]$Once,
    [string]$InputFile
)

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Inbox = Join-Path $Root "inbox"
$Output = Join-Path $Root "pdf_output"
$WorkRoot = Join-Path $Root ".service-work"
$LogRoot = Join-Path $Root "service_logs"
$Renderer = Join-Path $Root "render_r_homework.ps1"

function New-DirectoryIfMissing {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force $Path | Out-Null
    }
}

function Get-SafeName {
    param([string]$Name)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $chars = $Name.ToCharArray() | ForEach-Object {
        if ($invalid -contains $_) { "_" } else { $_ }
    }
    return (-join $chars)
}

function Invoke-RenderJob {
    param([string]$SourceFile)

    $source = (Resolve-Path -LiteralPath $SourceFile).Path
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($source)
    $fileName = [System.IO.Path]::GetFileName($source)
    $safeBase = Get-SafeName $baseName
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $jobDir = Join-Path $WorkRoot "$safeBase-$stamp"
    $jobInput = Join-Path $jobDir $fileName
    $logPath = Join-Path $LogRoot "$safeBase-$stamp.log"

    New-DirectoryIfMissing $jobDir
    Copy-Item -LiteralPath $source -Destination $jobInput -Force

    Write-Host ""
    Write-Host "Processing: $source"
    Write-Host "Working directory: $jobDir"

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $Renderer $jobInput *> $logPath
    $code = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference

    $jobPdf = Join-Path $jobDir "$baseName.pdf"
    if ($code -eq 0 -and (Test-Path $jobPdf)) {
        $destPdf = Join-Path $Output "$baseName.pdf"
        Copy-Item -LiteralPath $jobPdf -Destination $destPdf -Force
        $extraFiles = Get-ChildItem -LiteralPath $jobDir -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -ne $jobPdf -and
                $_.Extension.ToLowerInvariant() -in @(".pdf", ".png", ".jpg", ".jpeg", ".svg")
            }
        foreach ($extra in $extraFiles) {
            $extraName = "$baseName-$($extra.Name)"
            Copy-Item -LiteralPath $extra.FullName -Destination (Join-Path $Output $extraName) -Force
        }
        Write-Host "Done: $destPdf"
        Write-Host "Log: $logPath"
        return $true
    }

    Write-Host "Failed. Log: $logPath"
    return $false
}

New-DirectoryIfMissing $Inbox
New-DirectoryIfMissing $Output
New-DirectoryIfMissing $WorkRoot
New-DirectoryIfMissing $LogRoot

if (-not (Test-Path $Renderer)) {
    throw "Renderer not found: $Renderer"
}

if ($Once) {
    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        throw "InputFile is required when using -Once."
    }
    $ok = Invoke-RenderJob -SourceFile $InputFile
    if (-not $ok) {
        exit 1
    }
    exit 0
}

Write-Host "R homework PDF service is running."
Write-Host "Put .r files into: $Inbox"
Write-Host "PDF files will appear in: $Output"
Write-Host "Close this window to stop the service."

$seen = @{}
while ($true) {
    $files = Get-ChildItem -LiteralPath $Inbox -Filter "*.r" -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $sig = "$($file.LastWriteTimeUtc.Ticks)-$($file.Length)"
        if ($seen.ContainsKey($file.FullName) -and $seen[$file.FullName] -eq $sig) {
            continue
        }

        Start-Sleep -Milliseconds 700
        $fresh = Get-Item -LiteralPath $file.FullName -ErrorAction SilentlyContinue
        if (-not $fresh) {
            continue
        }
        $freshSig = "$($fresh.LastWriteTimeUtc.Ticks)-$($fresh.Length)"
        if ($freshSig -ne $sig) {
            continue
        }

        $seen[$file.FullName] = $sig
        [void](Invoke-RenderJob -SourceFile $file.FullName)
    }

    Start-Sleep -Seconds 3
}
