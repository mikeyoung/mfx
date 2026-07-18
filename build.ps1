$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = $PSScriptRoot
$soundDirectory = Join-Path $projectRoot 'snd'
$templatePath = Join-Path $projectRoot 'src\index.template.html'
$serviceWorkerTemplatePath = Join-Path $projectRoot 'src\sw.template.js'
$outputPath = Join-Path $projectRoot 'index.html'
$serviceWorkerOutputPath = Join-Path $projectRoot 'sw.js'
$manifestPath = Join-Path $projectRoot 'manifest.webmanifest'
$icon192Path = Join-Path $projectRoot 'icon-192.png'
$icon512Path = Join-Path $projectRoot 'icon-512.png'
$appVersionPath = Join-Path $projectRoot 'VERSION'
$supportedExtensions = @('.mp3', '.wav', '.ogg', '.m4a', '.aac', '.flac', '.opus', '.webm')

if (-not (Test-Path -LiteralPath $soundDirectory -PathType Container)) {
  throw "Sound directory not found: $soundDirectory"
}
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
  throw "Page template not found: $templatePath"
}
if (-not (Test-Path -LiteralPath $serviceWorkerTemplatePath -PathType Leaf)) {
  throw "Service-worker template not found: $serviceWorkerTemplatePath"
}
foreach ($pwaAsset in @($manifestPath, $icon192Path, $icon512Path)) {
  if (-not (Test-Path -LiteralPath $pwaAsset -PathType Leaf)) {
    throw "PWA asset not found: $pwaAsset"
  }
}
if (-not (Test-Path -LiteralPath $appVersionPath -PathType Leaf)) {
  throw "Version file not found: $appVersionPath"
}
$appVersion = [System.IO.File]::ReadAllText($appVersionPath).Trim()
if ($appVersion -notmatch '^\d+\.\d+$') {
  throw "VERSION must contain a major.minor number, such as 9.1."
}

$soundRoot = (Resolve-Path -LiteralPath $soundDirectory).Path.TrimEnd('\')
$audioFiles = @(
  Get-ChildItem -LiteralPath $soundRoot -File -Recurse |
    Where-Object { $supportedExtensions -contains $_.Extension.ToLowerInvariant() } |
    Sort-Object FullName
)

if ($audioFiles.Count -eq 0) {
  throw "No supported audio files were found in $soundRoot"
}

$files = @(
  $audioFiles |
    ForEach-Object { $_.FullName.Substring($soundRoot.Length + 1).Replace('\', '/') }
)
$manifest = ConvertTo-Json -InputObject $files -Compress

$versionRecords = for ($index = 0; $index -lt $audioFiles.Count; $index += 1) {
  "$($files[$index])|$($audioFiles[$index].Length)|$($audioFiles[$index].LastWriteTimeUtc.Ticks)"
}
$versionSource = $versionRecords -join "`n"
$versionBytes = [System.Text.Encoding]::UTF8.GetBytes($versionSource)
$versionHash = [System.Security.Cryptography.SHA256]::HashData($versionBytes)
$shortHash = ([System.Convert]::ToHexString($versionHash)).Substring(0, 12).ToLowerInvariant()
$cacheName = "mfx-sounds-v2-$shortHash"

$shellVersionRecords = @($shortHash, "app-version|$appVersion")
foreach ($shellSource in @(
  $templatePath,
  $serviceWorkerTemplatePath,
  $manifestPath,
  $icon192Path,
  $icon512Path
)) {
  $shellBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $shellSource).Path)
  $shellDigest = [System.Convert]::ToHexString(
    [System.Security.Cryptography.SHA256]::HashData($shellBytes)
  )
  $shellVersionRecords += "$(Split-Path -Leaf $shellSource)|$shellDigest"
}
$shellVersionSource = $shellVersionRecords -join "`n"
$shellVersionBytes = [System.Text.Encoding]::UTF8.GetBytes($shellVersionSource)
$shellVersionHash = [System.Security.Cryptography.SHA256]::HashData($shellVersionBytes)
$shellShortHash = ([System.Convert]::ToHexString($shellVersionHash)).Substring(0, 12).ToLowerInvariant()
$shellCacheName = "mfx-shell-$shellShortHash"

$template = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $templatePath).Path)
$output = $template.Replace('__SOUND_FILES__', $manifest).Replace(
  '__CACHE_NAME__',
  $cacheName
).Replace('__APP_VERSION__', $appVersion)
[System.IO.File]::WriteAllText(
  $outputPath,
  $output,
  [System.Text.UTF8Encoding]::new($false)
)

$serviceWorkerTemplate = [System.IO.File]::ReadAllText(
  (Resolve-Path -LiteralPath $serviceWorkerTemplatePath).Path
)
$serviceWorker = $serviceWorkerTemplate.Replace('__CACHE_NAME__', $cacheName).Replace(
  '__SHELL_CACHE_NAME__',
  $shellCacheName
)
[System.IO.File]::WriteAllText(
  $serviceWorkerOutputPath,
  $serviceWorker,
  [System.Text.UTF8Encoding]::new($false)
)

Write-Output "Generated Mellotron Sound Effects $appVersion with $($files.Count) sound files."
