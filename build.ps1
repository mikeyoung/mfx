$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = $PSScriptRoot
$soundDirectory = Join-Path $projectRoot 'snd'
$templatePath = Join-Path $projectRoot 'src\index.template.html'
$serviceWorkerTemplatePath = Join-Path $projectRoot 'src\sw.template.js'
$outputPath = Join-Path $projectRoot 'index.html'
$serviceWorkerOutputPath = Join-Path $projectRoot 'sw.js'
$soundPackPath = Join-Path $projectRoot 'sounds.pack'
$soundPackTempPath = Join-Path $projectRoot 'sounds.pack.tmp'
$manifestPath = Join-Path $projectRoot 'manifest.webmanifest'
$iconSizes = @(16, 32, 48, 57, 60, 72, 76, 96, 114, 120, 128, 144, 152, 167, 180, 192, 196, 256, 384, 512, 1024)
$iconPaths = $iconSizes | ForEach-Object { Join-Path $projectRoot ("icon-$_.png") }
$appleTouchIconPath = Join-Path $projectRoot 'apple-touch-icon.png'
$iconMask192Path = Join-Path $projectRoot 'icon-maskable-192.png'
$iconMask512Path = Join-Path $projectRoot 'icon-maskable-512.png'
$appVersionPath = Join-Path $projectRoot 'VERSION'
$supportedExtensions = @('.mp3')

function ConvertTo-HexString {
  param([Parameter(Mandatory)][byte[]]$Bytes)

  return [System.BitConverter]::ToString($Bytes).Replace('-', '')
}

function Get-Sha256Hex {
  param([Parameter(Mandatory)][byte[]]$Bytes)

  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ConvertTo-HexString -Bytes ($algorithm.ComputeHash($Bytes))
  }
  finally {
    $algorithm.Dispose()
  }
}

if (-not (Test-Path -LiteralPath $soundDirectory -PathType Container)) {
  throw "Sound directory not found: $soundDirectory"
}
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
  throw "Page template not found: $templatePath"
}
if (-not (Test-Path -LiteralPath $serviceWorkerTemplatePath -PathType Leaf)) {
  throw "Service-worker template not found: $serviceWorkerTemplatePath"
}
foreach ($pwaAsset in @($manifestPath) + $iconPaths + @($appleTouchIconPath, $iconMask192Path, $iconMask512Path)) {
  if (-not (Test-Path -LiteralPath $pwaAsset -PathType Leaf)) {
    throw "PWA asset not found: $pwaAsset"
  }
}
if (-not (Test-Path -LiteralPath $appVersionPath -PathType Leaf)) {
  throw "Version file not found: $appVersionPath"
}
$appVersion = [System.IO.File]::ReadAllText($appVersionPath).Trim()
if ($appVersion -notmatch '^9+$') {
  throw "VERSION must contain only one or more 9 digits, such as 9, 99, or 999."
}

$soundRoot = (Resolve-Path -LiteralPath $soundDirectory).Path.TrimEnd('\\')
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
    ForEach-Object { $_.FullName.Substring($soundRoot.Length + 1).Replace('\\', '/') }
)
$soundRecords = [System.Collections.Generic.List[object]]::new($audioFiles.Count)
$packStream = $null
try {
  $packStream = [System.IO.File]::Open(
    $soundPackTempPath,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
  )
  $offset = [long]0
  for ($index = 0; $index -lt $audioFiles.Count; $index += 1) {
    $audioFile = $audioFiles[$index]
    $length = [long]$audioFile.Length
    $soundRecords.Add([ordered]@{
      n = $files[$index]
      o = $offset
      l = $length
    })
    $inputStream = $null
    try {
      $inputStream = [System.IO.File]::OpenRead($audioFile.FullName)
      $inputStream.CopyTo($packStream, 131072)
    }
    finally {
      if ($null -ne $inputStream) { $inputStream.Dispose() }
    }
    $offset += $length
  }
}
finally {
  if ($null -ne $packStream) { $packStream.Dispose() }
}
if (Test-Path -LiteralPath $soundPackPath -PathType Leaf) {
  # File.Replace is available in Windows PowerShell 5.1 and preserves the
  # atomic same-volume replacement used by the PowerShell 7 Move overload.
  $soundPackBackupPath = "$soundPackPath.previous"
  if (Test-Path -LiteralPath $soundPackBackupPath) {
    Remove-Item -LiteralPath $soundPackBackupPath -Force
  }
  [System.IO.File]::Replace(
    $soundPackTempPath,
    $soundPackPath,
    $soundPackBackupPath
  )
  Remove-Item -LiteralPath $soundPackBackupPath -Force
}
else {
  [System.IO.File]::Move($soundPackTempPath, $soundPackPath)
}

$packSize = [long](Get-Item -LiteralPath $soundPackPath).Length
if ($packSize -ne $offset) {
  throw "Generated sound pack size did not match its index."
}
$manifest = ConvertTo-Json -InputObject $soundRecords -Compress
$packHashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
$packHashStream = $null
try {
  $packHashStream = [System.IO.File]::OpenRead($soundPackPath)
  $packHash = $packHashAlgorithm.ComputeHash($packHashStream)
}
finally {
  if ($null -ne $packHashStream) { $packHashStream.Dispose() }
  $packHashAlgorithm.Dispose()
}
$shortHash = (ConvertTo-HexString -Bytes $packHash).Substring(0, 12).ToLowerInvariant()
$cacheName = "csfx-sound-pack-v1-$shortHash"

$shellVersionRecords = @($shortHash, "app-version|$appVersion")
foreach ($shellSource in @(
  $templatePath,
  $serviceWorkerTemplatePath,
  $manifestPath
) + $iconPaths + @($appleTouchIconPath, $iconMask192Path, $iconMask512Path)) {
  $shellBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $shellSource).Path)
  $shellDigest = Get-Sha256Hex -Bytes $shellBytes
  $shellVersionRecords += "$(Split-Path -Leaf $shellSource)|$shellDigest"
}
$shellVersionSource = $shellVersionRecords -join "`n"
$shellVersionBytes = [System.Text.Encoding]::UTF8.GetBytes($shellVersionSource)
$shellShortHash = (Get-Sha256Hex -Bytes $shellVersionBytes).Substring(0, 12).ToLowerInvariant()
$shellCacheName = "csfx-shell-$shellShortHash"

$template = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $templatePath).Path)
$output = $template.Replace('__SOUND_FILES__', $manifest).Replace(
  '__CACHE_NAME__',
  $cacheName
).Replace('__APP_VERSION__', $appVersion)
$output = $output.Replace('__SHELL_CACHE_NAME__', $shellCacheName).Replace(
  '__SOUND_PACK_VERSION__',
  $shortHash
).Replace('__SOUND_PACK_SIZE__', [string]$packSize)
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
).Replace('__APP_VERSION__', $appVersion)
$serviceWorker = $serviceWorker.Replace(
  '__SOUND_PACK_VERSION__',
  $shortHash
)
[System.IO.File]::WriteAllText(
  $serviceWorkerOutputPath,
  $serviceWorker,
  [System.Text.UTF8Encoding]::new($false)
)

Write-Output "Generated Chaotic Sound Effects $appVersion with $($files.Count) sounds in a $([math]::Round($packSize / 1MB, 2)) MiB pack."
