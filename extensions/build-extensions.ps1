param(
  [switch]$RebuildApp
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$extensionRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $extensionRoot
$distributionRoot = Join-Path $extensionRoot 'dist'
$artifactRoot = Join-Path $extensionRoot 'artifacts'
$appBuildPath = Join-Path $projectRoot 'build.ps1'
$appPagePath = Join-Path $projectRoot 'index.html'
$versionPath = Join-Path $projectRoot 'VERSION'
$soundPackPath = Join-Path $projectRoot 'sounds.pack'
$mediaNoticePath = Join-Path $projectRoot 'MEDIA-NOTICE.md'
$manifestRoot = Join-Path $extensionRoot 'manifests'
$sourceRoot = Join-Path $extensionRoot 'src'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Reset-GeneratedDirectory {
  param([Parameter(Mandatory)][string]$Path)

  $resolvedExtensionRoot = [System.IO.Path]::GetFullPath($extensionRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $resolvedPath = [System.IO.Path]::GetFullPath($Path)
  $expectedPrefix = $resolvedExtensionRoot + [System.IO.Path]::DirectorySeparatorChar
  if (-not $resolvedPath.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace a generated directory outside $resolvedExtensionRoot"
  }

  if (Test-Path -LiteralPath $resolvedPath) {
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
  }
  New-Item -ItemType Directory -Path $resolvedPath -Force | Out-Null
}

function Copy-RequiredFile {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Required extension asset not found: $Source"
  }
  Copy-Item -LiteralPath $Source -Destination $Destination
}

function Assert-StoreManifest {
  param(
    [Parameter(Mandatory)]
    [ValidateSet('chrome', 'firefox')]
    [string]$PackageName,

    [Parameter(Mandatory)][string]$ManifestText,
    [Parameter(Mandatory)][string]$ExpectedVersion
  )

  try {
    $manifest = ConvertFrom-Json -InputObject $ManifestText -ErrorAction Stop
  }
  catch {
    throw "$PackageName manifest is not valid JSON: $($_.Exception.Message)"
  }

  if ($manifest.manifest_version -ne 3) {
    throw "$PackageName manifest must use Manifest V3."
  }
  if ($manifest.name -ne 'Chaotic Sound Effects') {
    throw "$PackageName manifest has the wrong extension name."
  }
  if ($manifest.version -ne $ExpectedVersion) {
    throw "$PackageName manifest version does not match VERSION."
  }
  if ($ManifestText -match '__[A-Z0-9_]+__') {
    throw "$PackageName manifest contains an unresolved build token."
  }
  $description = [string]$manifest.description
  $expectedDescription = 'Creates an endless five-track stereo collage from a library of sound effects.'
  if ($description -ne $expectedDescription -or $description.Length -gt 132) {
    throw "$PackageName manifest does not contain the approved store description."
  }
  if ([string]$manifest.homepage_url -notmatch '^https://') {
    throw "$PackageName manifest homepage_url must use HTTPS."
  }

  foreach ($permissionKey in @('permissions', 'host_permissions', 'optional_permissions', 'optional_host_permissions')) {
    $permissionProperty = $manifest.PSObject.Properties[$permissionKey]
    if ($null -ne $permissionProperty -and @($permissionProperty.Value).Count -gt 0) {
      throw "$PackageName manifest unexpectedly requests $permissionKey."
    }
  }

  $background = $manifest.PSObject.Properties['background'].Value
  if ($PackageName -eq 'chrome') {
    if ([string]$background.service_worker -ne 'background.js') {
      throw 'Chrome manifest must use background.js as its service worker.'
    }
    if ($null -ne $background.PSObject.Properties['scripts']) {
      throw 'Chrome manifest must not declare background.scripts.'
    }
    if ($null -ne $manifest.PSObject.Properties['browser_specific_settings']) {
      throw 'Chrome manifest must not contain Firefox-specific settings.'
    }
  }
  else {
    $backgroundScripts = @($background.scripts)
    if ($backgroundScripts.Count -ne 1 -or $backgroundScripts[0] -ne 'background.js') {
      throw 'Firefox manifest must use background.js as its event-page script.'
    }
    if ($null -ne $background.PSObject.Properties['service_worker']) {
      throw 'Firefox manifest must not declare an unsupported background service worker.'
    }

    $gecko = $manifest.browser_specific_settings.gecko
    if ([string]$gecko.id -ne 'chaotic-sound-effects@mikeyoung.org') {
      throw 'Firefox manifest has the wrong stable extension ID.'
    }
    $requiredData = @($gecko.data_collection_permissions.required)
    if ($requiredData.Count -ne 1 -or $requiredData[0] -ne 'none') {
      throw 'Firefox manifest must declare that it requires no data collection.'
    }
  }
}

if ($RebuildApp) {
  & $appBuildPath
}

foreach ($requiredPath in @(
  $appPagePath,
  $versionPath,
  $soundPackPath,
  $mediaNoticePath,
  (Join-Path $sourceRoot 'background.js'),
  (Join-Path $manifestRoot 'chrome.json'),
  (Join-Path $manifestRoot 'firefox.json')
)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required extension input not found: $requiredPath"
  }
}

$appVersion = [System.IO.File]::ReadAllText($versionPath).Trim()
if ($appVersion -notmatch '^\d+\.\d+$') {
  throw 'VERSION must contain a major.minor number, such as 9.1.'
}

$page = [System.IO.File]::ReadAllText($appPagePath)
if ($page -notmatch [regex]::Escape("const APP_VERSION = `"$appVersion`";")) {
  throw 'index.html is stale. Run build.ps1 or use -RebuildApp first.'
}
if ($page -notmatch 'const EXTENSION_RUNTIME =') {
  throw 'index.html does not contain the extension runtime guard. Rebuild the app first.'
}

$styleExpression = [regex]::new('<style>\s*(?<content>.*?)\s*</style>', 'Singleline')
$scriptExpression = [regex]::new('<script>\s*(?<content>.*?)\s*</script>', 'Singleline')
$styleMatches = $styleExpression.Matches($page)
$scriptMatches = $scriptExpression.Matches($page)
if ($styleMatches.Count -ne 1 -or $scriptMatches.Count -ne 1) {
  throw "Expected exactly one inline style and one inline script in index.html."
}

$appCss = $styleMatches[0].Groups['content'].Value.Trim() + "`n"
$appJavaScript = $scriptMatches[0].Groups['content'].Value.Trim() + "`n"
$extensionPage = $styleExpression.Replace(
  $page,
  '  <link rel="stylesheet" href="./app.css">',
  1
)
$extensionPage = $scriptExpression.Replace(
  $extensionPage,
  '  <script src="./app.js"></script>',
  1
)

# Web app installation metadata does not apply inside an extension page. The
# toolbar and store listing use the packaged manifest and icons instead.
$extensionPage = [regex]::Replace(
  $extensionPage,
  '(?m)^\s*<meta name="(?:mobile-web-app-capable|apple-mobile-web-app-capable|apple-mobile-web-app-status-bar-style)"[^>]*>\r?\n',
  ''
)
$extensionPage = [regex]::Replace(
  $extensionPage,
  '(?m)^\s*<link rel="(?:manifest|icon|apple-touch-icon)"[^>]*>\r?\n',
  ''
)
$extensionPage = $extensionPage.Replace(
  '  <title>Chaotic Sound Effects</title>',
  "  <link rel=`"icon`" href=`"./icon-32.png`" sizes=`"32x32`" type=`"image/png`">`r`n  <title>Chaotic Sound Effects</title>"
)
$extensionPage = [regex]::Replace(
  $extensionPage,
  '(?m)^\s*<p class="offline-note">.*?</p>\r?\n',
  "    <p class=`"offline-note`">The complete sound library is included and available offline.</p>`r`n"
)

if ($extensionPage -match '<script(?![^>]*\bsrc=)') {
  throw 'The generated extension page still contains inline JavaScript.'
}
foreach ($buildToken in @(
  '__APP_VERSION__',
  '__SOUND_FILES__',
  '__CACHE_NAME__',
  '__SHELL_CACHE_NAME__',
  '__SOUND_PACK_VERSION__',
  '__SOUND_PACK_SIZE__'
)) {
  if ($extensionPage.Contains($buildToken) -or $appJavaScript.Contains($buildToken)) {
    throw "The generated extension contains unresolved build token $buildToken"
  }
}

Reset-GeneratedDirectory -Path $distributionRoot
if (-not (Test-Path -LiteralPath $artifactRoot)) {
  New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
}

$iconSizes = @(16, 32, 48, 96, 128)
$packageNames = @('chrome', 'firefox')
foreach ($packageName in $packageNames) {
  $packageRoot = Join-Path $distributionRoot $packageName
  New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

  [System.IO.File]::WriteAllText(
    (Join-Path $packageRoot 'index.html'),
    $extensionPage,
    $utf8NoBom
  )
  [System.IO.File]::WriteAllText(
    (Join-Path $packageRoot 'app.css'),
    $appCss,
    $utf8NoBom
  )
  [System.IO.File]::WriteAllText(
    (Join-Path $packageRoot 'app.js'),
    $appJavaScript,
    $utf8NoBom
  )

  $manifestTemplatePath = Join-Path $manifestRoot "$packageName.json"
  $manifest = [System.IO.File]::ReadAllText($manifestTemplatePath).Replace(
    '__APP_VERSION__',
    $appVersion
  )
  Assert-StoreManifest `
    -PackageName $packageName `
    -ManifestText $manifest `
    -ExpectedVersion $appVersion
  [System.IO.File]::WriteAllText(
    (Join-Path $packageRoot 'manifest.json'),
    $manifest,
    $utf8NoBom
  )

  Copy-RequiredFile -Source (Join-Path $sourceRoot 'background.js') -Destination $packageRoot
  Copy-RequiredFile -Source $soundPackPath -Destination $packageRoot
  Copy-RequiredFile -Source (Join-Path $projectRoot 'LICENSE') -Destination $packageRoot
  Copy-RequiredFile -Source $mediaNoticePath -Destination $packageRoot
  foreach ($iconSize in $iconSizes) {
    Copy-RequiredFile -Source (Join-Path $projectRoot "icon-$iconSize.png") -Destination $packageRoot
  }

  $archivePath = Join-Path $artifactRoot "chaotic-sound-effects-$packageName-v$appVersion.zip"
  if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
  }
  Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal

  $archiveMiB = [math]::Round((Get-Item -LiteralPath $archivePath).Length / 1MB, 2)
  Write-Output "Built $packageName extension $appVersion ($archiveMiB MiB): $archivePath"
}
