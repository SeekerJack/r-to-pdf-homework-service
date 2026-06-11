param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputFile
)

$ErrorActionPreference = "Stop"

function Convert-ToRString {
    param([string]$Path)
    return ($Path -replace "\\", "/" -replace "'", "\\'")
}

function Escape-YamlText {
    param([string]$Text)
    return ($Text -replace "\\", "\\\\" -replace '"', '\"')
}

function Get-CommentText {
    param([string]$Line)
    if ($Line -match '^\s*#\s*(.*)$') {
        return $Matches[1].Trim()
    }
    return $null
}

function Get-SafeChunkId {
    param(
        [string]$Title,
        [int]$Index
    )

    $id = $Title.ToLowerInvariant()
    $id = $id -replace '\s+', '-'
    $id = $id -replace '[^a-z0-9-]+', '-'
    $id = $id.Trim('-')
    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = "section-$Index"
    }
    return "hw_$id"
}

function Get-RscriptPath {
    $default = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
    if (Test-Path $default) {
        return $default
    }

    $cmd = Get-Command Rscript -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    throw "Rscript was not found. Please install R or add Rscript to PATH."
}

function Invoke-XeLaTeX {
    param(
        [string]$XeLaTeXPath,
        [string]$TexPath,
        [string]$WorkDir
    )

    Push-Location $WorkDir
    try {
        & $XeLaTeXPath -interaction=nonstopmode -halt-on-error (Split-Path $TexPath -Leaf) | Out-Host
        $code = $LASTEXITCODE
        return [int]$code
    }
    finally {
        Pop-Location
    }
}

function Assert-CodeBlocksMatchSource {
    param(
        [string[]]$SourceLines,
        [string]$RmdPath
    )

    $rmdLines = [System.IO.File]::ReadAllLines($RmdPath, [System.Text.UTF8Encoding]::new($false, $true))
    $codeLines = [System.Collections.Generic.List[string]]::new()
    $inside = $false

    foreach ($line in $rmdLines) {
        if ($line.StartsWith('````{r hw_')) {
            $inside = $true
            continue
        }
        if ($inside -and $line -eq '````') {
            $inside = $false
            continue
        }
        if ($inside) {
            [void]$codeLines.Add($line)
        }
    }

    if ($SourceLines.Count -ne $codeLines.Count) {
        throw "Content check failed: source has $($SourceLines.Count) lines, Rmd code blocks have $($codeLines.Count) lines."
    }

    for ($i = 0; $i -lt $SourceLines.Count; $i++) {
        if ($SourceLines[$i] -cne $codeLines[$i]) {
            throw "Content check failed: line $($i + 1) differs."
        }
    }
}

function Get-InstallPackageNames {
    param([string[]]$Lines)

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        $matches = [regex]::Matches($line, 'install\.packages\s*\(\s*["'']([^"'']+)["'']')
        foreach ($match in $matches) {
            $pkg = $match.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($pkg) -and -not $names.Contains($pkg)) {
                [void]$names.Add($pkg)
            }
        }
    }
    return @($names)
}

function Read-CranPackagesIndex {
    param([string]$IndexPath)

    $records = @{}
    $text = Get-Content -Raw -Encoding UTF8 $IndexPath
    $blocks = [regex]::Split($text.Trim(), "(\r?\n){2,}")
    foreach ($block in $blocks) {
        if ($block -notmatch '^Package:\s*(.+)$') {
            continue
        }
        $record = @{}
        $current = $null
        foreach ($line in ($block -split "\r?\n")) {
            if ($line -match '^([A-Za-z][A-Za-z0-9.]*):\s*(.*)$') {
                $current = $Matches[1]
                $record[$current] = $Matches[2]
            }
            elseif ($current -and $line -match '^\s+(.+)$') {
                $record[$current] += " " + $Matches[1]
            }
        }
        if ($record.ContainsKey("Package")) {
            $records[$record["Package"]] = $record
        }
    }
    return $records
}

function Get-CranDependencies {
    param([hashtable]$Record)

    $deps = [System.Collections.Generic.List[string]]::new()
    foreach ($field in @("Depends", "Imports", "LinkingTo")) {
        if (-not $Record.ContainsKey($field)) {
            continue
        }
        foreach ($part in ($Record[$field] -split ",")) {
            $name = ($part.Trim() -replace '\s*\(.*?\)', '').Trim()
            if ($name -and $name -ne "R" -and -not $deps.Contains($name)) {
                [void]$deps.Add($name)
            }
        }
    }
    return @($deps)
}

function Invoke-CurlDownload {
    param(
        [string]$Url,
        [string]$OutputPath
    )

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & curl.exe --ssl-no-revoke -sS -L --retry 3 --output $OutputPath $Url
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutputPath)) {
            return
        }

        & curl.exe -k -sS -L --retry 3 --output $OutputPath $Url
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutputPath)) {
            return
        }
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    throw "Failed to download: $Url"
}

function Install-CranBinaryPackage {
    param(
        [string]$Package,
        [hashtable]$Index,
        [string]$Repo,
        [string]$LibPath,
        [string]$DownloadDir,
        [hashtable]$Seen
    )

    if ($Seen.ContainsKey($Package)) {
        return
    }
    $Seen[$Package] = $true

    $packageDir = Join-Path $LibPath $Package
    if (Test-Path (Join-Path $packageDir "DESCRIPTION")) {
        return
    }

    if (-not $Index.ContainsKey($Package)) {
        Write-Host "CRAN package not found in binary index, skipping preinstall: $Package"
        return
    }

    $record = $Index[$Package]
    foreach ($dep in (Get-CranDependencies -Record $record)) {
        Install-CranBinaryPackage -Package $dep -Index $Index -Repo $Repo -LibPath $LibPath -DownloadDir $DownloadDir -Seen $Seen
    }

    $version = $record["Version"]
    $zipName = "$Package" + "_" + "$version.zip"
    $url = "$Repo/bin/windows/contrib/4.5/$zipName"
    $zipPath = Join-Path $DownloadDir $zipName

    Write-Host "Preinstalling R package: $Package $version"
    try {
        Invoke-CurlDownload -Url $url -OutputPath $zipPath
    }
    catch {
        Write-Host "Warning: failed to preinstall R package $Package. R code may still handle it."
        return
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $LibPath -Force
}

function Install-RequestedRPackages {
    param(
        [string[]]$Packages,
        [string]$LibPath,
        [string]$DownloadDir
    )

    if ($Packages.Count -eq 0) {
        return
    }

    New-Item -ItemType Directory -Force $LibPath | Out-Null
    New-Item -ItemType Directory -Force $DownloadDir | Out-Null

    $repo = "https://cran.rstudio.com"
    $indexPath = Join-Path $DownloadDir "PACKAGES"
    try {
        Invoke-CurlDownload -Url "$repo/bin/windows/contrib/4.5/PACKAGES" -OutputPath $indexPath
    }
    catch {
        Write-Host "Warning: failed to download CRAN package index. Continuing without preinstall."
        return
    }

    $index = Read-CranPackagesIndex -IndexPath $indexPath
    $seen = @{}
    foreach ($pkg in $Packages) {
        Install-CranBinaryPackage -Package $pkg -Index $index -Repo $repo -LibPath $LibPath -DownloadDir $DownloadDir -Seen $seen
    }
}

$sourcePath = (Resolve-Path -LiteralPath $InputFile).Path
$sourceDir = Split-Path $sourcePath -Parent
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
$rmdPath = Join-Path $sourceDir "$baseName.Rmd"
$texPath = Join-Path $sourceDir "$baseName.tex"
$pdfPath = Join-Path $sourceDir "$baseName.pdf"
$logPath = Join-Path $sourceDir "$baseName.log"

$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$sourceLines = [System.IO.File]::ReadAllLines($sourcePath, $utf8Strict)
$requestedInstallPackages = Get-InstallPackageNames -Lines $sourceLines

$commentLines = @()
foreach ($line in $sourceLines) {
    $comment = Get-CommentText $line
    if ($null -ne $comment -and $comment.Length -gt 0) {
        $commentLines += $comment
    }
    if ($commentLines.Count -ge 6) {
        break
    }
}

$title = $baseName
foreach ($comment in $commentLines) {
    if ($comment -match '\d{6,}') {
        continue
    }
    if ($comment -notmatch '^\s*P\s*\d+') {
        $title = $comment
        break
    }
}

$author = ""
foreach ($comment in $commentLines) {
    if ($comment -match '\d{6,}') {
        $author = $comment
        break
    }
}

$problemPattern = '^\s*#\s*P\s*\d+\s*[\uFF0C,]?\s*[\d.]+'
$markerIndexes = [System.Collections.Generic.List[int]]::new()
for ($i = 0; $i -lt $sourceLines.Count; $i++) {
    if ($sourceLines[$i] -match $problemPattern) {
        [void]$markerIndexes.Add($i)
    }
}

$sections = @()
if ($markerIndexes.Count -eq 0) {
    $sections += [pscustomobject]@{
        Start = 0
        End = $sourceLines.Count - 1
        Marker = 0
        Title = "Full Code"
    }
}
else {
    $starts = [System.Collections.Generic.List[int]]::new()
    [void]$starts.Add(0)

    for ($m = 1; $m -lt $markerIndexes.Count; $m++) {
        $start = $markerIndexes[$m]
        while ($start -gt 0 -and [string]::IsNullOrWhiteSpace($sourceLines[$start - 1])) {
            $start--
        }
        [void]$starts.Add($start)
    }

    for ($s = 0; $s -lt $starts.Count; $s++) {
        $start = $starts[$s]
        $end = if ($s -lt $starts.Count - 1) { $starts[$s + 1] - 1 } else { $sourceLines.Count - 1 }
        $marker = $markerIndexes[$s]
        $titleText = (Get-CommentText $sourceLines[$marker])
        $titleText = $titleText -replace '\s+', ' '
        $sections += [pscustomobject]@{
            Start = $start
            End = $end
            Marker = $marker
            Title = $titleText
        }
    }
}

$rmd = [System.Collections.Generic.List[string]]::new()
[void]$rmd.Add("---")
[void]$rmd.Add('title: "' + (Escape-YamlText $title) + '"')
if (-not [string]::IsNullOrWhiteSpace($author)) {
    [void]$rmd.Add('author: "' + (Escape-YamlText $author) + '"')
}
[void]$rmd.Add('date: "`r format(Sys.Date(), ''%Y-%m-%d'')`"')
[void]$rmd.Add("documentclass: ctexart")
[void]$rmd.Add("output:")
[void]$rmd.Add("  pdf_document:")
[void]$rmd.Add("    latex_engine: xelatex")
[void]$rmd.Add("    toc: true")
[void]$rmd.Add("    toc_depth: 2")
[void]$rmd.Add("    number_sections: false")
[void]$rmd.Add("    highlight: tango")
[void]$rmd.Add("    fig_caption: true")
[void]$rmd.Add("    keep_tex: true")
[void]$rmd.Add("geometry: `"a4paper,margin=2.2cm`"")
[void]$rmd.Add("fontsize: 11pt")
[void]$rmd.Add("header-includes:")
[void]$rmd.Add("  - \usepackage{fancyhdr}")
[void]$rmd.Add("  - \usepackage{xcolor}")
[void]$rmd.Add("  - \usepackage{titlesec}")
[void]$rmd.Add("  - \usepackage{fvextra}")
[void]$rmd.Add("  - \usepackage{caption}")
[void]$rmd.Add("  - \usepackage{float}")
[void]$rmd.Add("  - \setlength{\headheight}{14pt}")
[void]$rmd.Add("  - \setmonofont{Consolas}")
[void]$rmd.Add("  - \pagestyle{fancy}")
[void]$rmd.Add("  - \fancyhf{}")
[void]$rmd.Add("  - \fancyhead[L]{$(Escape-YamlText $title)}")
if (-not [string]::IsNullOrWhiteSpace($author)) {
    [void]$rmd.Add("  - \fancyhead[R]{$(Escape-YamlText $author)}")
}
[void]$rmd.Add("  - \fancyfoot[C]{\thepage}")
[void]$rmd.Add("  - \definecolor{sectionblue}{HTML}{1F4E79}")
[void]$rmd.Add("  - \definecolor{subgray}{HTML}{4A5568}")
[void]$rmd.Add("  - \titleformat{\section}{\Large\bfseries\color{sectionblue}}{}{0em}{}")
[void]$rmd.Add("  - \titleformat{\subsection}{\large\bfseries\color{subgray}}{}{0em}{}")
[void]$rmd.Add("  - \captionsetup{font=small,labelfont=bf}")
[void]$rmd.Add("  - \DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,commandchars=\\\{\}}")
[void]$rmd.Add("---")
[void]$rmd.Add("")
[void]$rmd.Add('```{r setup, include=FALSE}')
[void]$rmd.Add('local_lib <- Sys.getenv("R_HOMEWORK_LIB", unset = "")')
[void]$rmd.Add('if (nzchar(local_lib)) {')
[void]$rmd.Add('  dir.create(local_lib, recursive = TRUE, showWarnings = FALSE)')
[void]$rmd.Add('  .libPaths(c(local_lib, .libPaths()))')
[void]$rmd.Add('}')
[void]$rmd.Add('options(repos = c(CRAN = "https://cloud.r-project.org"))')
[void]$rmd.Add('r_homework_install_packages <- utils::install.packages')
[void]$rmd.Add('install.packages <- function(pkgs, ...) {')
[void]$rmd.Add('  try(r_homework_install_packages(pkgs, ...), silent = TRUE)')
[void]$rmd.Add('  invisible(NULL)')
[void]$rmd.Add('}')
[void]$rmd.Add('r_homework_library <- base::library')
[void]$rmd.Add('library <- function(package, ..., character.only = FALSE) {')
[void]$rmd.Add('  pkg <- if (character.only) as.character(package) else deparse(substitute(package))')
[void]$rmd.Add('  if (identical(pkg, "showtext") && !requireNamespace("showtext", quietly = TRUE)) {')
[void]$rmd.Add('    showtext_auto <<- function(...) invisible(TRUE)')
[void]$rmd.Add('    return(invisible(TRUE))')
[void]$rmd.Add('  }')
[void]$rmd.Add('  r_homework_library(pkg, ..., character.only = TRUE)')
[void]$rmd.Add('}')
[void]$rmd.Add('if (!exists("showtext_auto", mode = "function")) showtext_auto <- function(...) invisible(TRUE)')
[void]$rmd.Add('preload_packages <- c("DescTools", "qcc", "plotrix", "RColorBrewer", "ggplot2", "ggiraphExtra", "gridExtra")')
[void]$rmd.Add('for (pkg in preload_packages) {')
[void]$rmd.Add('  if (requireNamespace(pkg, quietly = TRUE)) {')
[void]$rmd.Add('    suppressPackageStartupMessages(library(pkg, character.only = TRUE))')
[void]$rmd.Add('  }')
[void]$rmd.Add('}')
[void]$rmd.Add("knitr::opts_chunk`$set(")
[void]$rmd.Add("  echo = TRUE,")
[void]$rmd.Add('  results = "markup",')
[void]$rmd.Add("  message = FALSE,")
[void]$rmd.Add("  warning = FALSE,")
[void]$rmd.Add('  fig.align = "center",')
[void]$rmd.Add("  fig.width = 7.2,")
[void]$rmd.Add("  fig.height = 5.2,")
[void]$rmd.Add("  dpi = 300,")
[void]$rmd.Add('  out.width = "92%"')
[void]$rmd.Add(")")
[void]$rmd.Add('```')

for ($s = 0; $s -lt $sections.Count; $s++) {
    $section = $sections[$s]
    $sectionTitle = $section.Title
    $chunkId = Get-SafeChunkId $sectionTitle ($s + 1)

    [void]$rmd.Add("")
    [void]$rmd.Add("\newpage")
    [void]$rmd.Add("")
    [void]$rmd.Add("# $sectionTitle")
    [void]$rmd.Add("")
    [void]$rmd.Add('````{r ' + $chunkId + ', fig.cap="' + $sectionTitle + ' generated figure"}')
    for ($lineIndex = $section.Start; $lineIndex -le $section.End; $lineIndex++) {
        [void]$rmd.Add($sourceLines[$lineIndex])
    }
    [void]$rmd.Add('````')
}

[System.IO.File]::WriteAllLines($rmdPath, $rmd, [System.Text.UTF8Encoding]::new($false))
Assert-CodeBlocksMatchSource -SourceLines $sourceLines -RmdPath $rmdPath

$tinyRoot = Join-Path $PSScriptRoot ".TinyTeX\TinyTeX"
$parentTinyRoot = Join-Path (Split-Path $PSScriptRoot -Parent) ".TinyTeX\TinyTeX"
$tinyRoots = @($tinyRoot, $parentTinyRoot)
$latexPathParts = @()
foreach ($candidateTinyRoot in $tinyRoots) {
    $candidateTinyBin = Join-Path $candidateTinyRoot "bin\windows"
    $candidateTinyPerl = Join-Path $candidateTinyRoot "tlpkg\tlperl\bin"
    $candidateXeLaTeX = Join-Path $candidateTinyBin "xelatex.exe"
    if (Test-Path $candidateXeLaTeX) {
        $xelatex = $candidateXeLaTeX
        $latexPathParts += $candidateTinyPerl
        $latexPathParts += $candidateTinyBin
        break
    }
}
if ($xelatex) {
}
else {
    $cmdXeLaTeX = Get-Command xelatex.exe -ErrorAction SilentlyContinue
    if (-not $cmdXeLaTeX) {
        $cmdXeLaTeX = Get-Command xelatex -ErrorAction SilentlyContinue
    }
    if (-not $cmdXeLaTeX) {
        throw "XeLaTeX was not found. Install TinyTeX in .TinyTeX or add xelatex to PATH."
    }
    $xelatex = $cmdXeLaTeX.Source
}

$rscript = Get-RscriptPath
$pandoc = Join-Path $env:LOCALAPPDATA "Pandoc"
$tmpDir = Join-Path $sourceDir ".render-tmp"
$localRLib = Join-Path $PSScriptRoot ".r-lib"
New-Item -ItemType Directory -Force $tmpDir | Out-Null
New-Item -ItemType Directory -Force $localRLib | Out-Null
Install-RequestedRPackages -Packages $requestedInstallPackages -LibPath $localRLib -DownloadDir $tmpDir

$env:TEMP = $tmpDir
$env:TMP = $tmpDir
$env:TMPDIR = $tmpDir
$env:R_HOMEWORK_LIB = $localRLib
$pathParts = @($latexPathParts + @("c:\rtools45\x86_64-w64-mingw32.static.posix\bin", "c:\rtools45\usr\bin", "C:\WINDOWS\system32", "C:\WINDOWS", "C:\WINDOWS\System32\Wbem", "C:\WINDOWS\System32\WindowsPowerShell\v1.0\", $pandoc, $env:PATH))
$env:PATH = ($pathParts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ";"

$rmdForR = Convert-ToRString $rmdPath
$texForR = Convert-ToRString $texPath
$renderExpr = "res <- try(rmarkdown::render('$rmdForR', output_format='pdf_document', encoding='UTF-8', clean=FALSE), silent=TRUE); if (!file.exists('$texForR')) { if (inherits(res, 'try-error')) cat(as.character(res), sep='\n'); stop('tex was not generated') }; cat('tex generated', '\n')"

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $rscript -e $renderExpr
$renderCode = $LASTEXITCODE
$ErrorActionPreference = $oldErrorActionPreference
if ($renderCode -ne 0) {
    throw "R Markdown did not generate tex. Please check the output above."
}

$exit = Invoke-XeLaTeX -XeLaTeXPath $xelatex -TexPath $texPath -WorkDir $sourceDir
if ($exit -ne 0) {
    throw "The first LaTeX pass failed. See log: $logPath"
}

$exit = Invoke-XeLaTeX -XeLaTeXPath $xelatex -TexPath $texPath -WorkDir $sourceDir
if ($exit -ne 0) {
    throw "The second LaTeX pass failed. See log: $logPath"
}

if (-not (Test-Path $pdfPath)) {
    throw "PDF was not generated: $pdfPath"
}

$logText = if (Test-Path $logPath) { Get-Content -Raw -Encoding UTF8 $logPath } else { "" }
foreach ($fatal in @("LaTeX Error", "Emergency stop", "Fatal")) {
    if ($logText -match [regex]::Escape($fatal)) {
        throw "The PDF log contains an error marker: $fatal"
    }
}

if (Test-Path $tmpDir) {
    $resolvedTmp = (Resolve-Path $tmpDir).Path
    $resolvedSourceDir = (Resolve-Path $sourceDir).Path
    if ($resolvedTmp.StartsWith($resolvedSourceDir)) {
        Remove-Item -LiteralPath $resolvedTmp -Recurse -Force
    }
}

Write-Host "Done: $pdfPath"
Write-Host "Rmd: $rmdPath"
Write-Host "Check: Rmd code blocks match the source R file line by line."
