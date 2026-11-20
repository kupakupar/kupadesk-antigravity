$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
function U([string]$b) { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) }

$BaseUrl = if ($env:KUPADESK_BASE_URL -and $env:KUPADESK_BASE_URL.Trim()) { $env:KUPADESK_BASE_URL.Trim().TrimEnd('/') } else { 'https://raw.githubusercontent.com/kupakupar/kupadesk-antigravity/main' }
$TargetDir = if ($env:KUPADESK_TARGET_DIR -and $env:KUPADESK_TARGET_DIR.Trim()) { $env:KUPADESK_TARGET_DIR.Trim() } else { Join-Path $env:USERPROFILE '.gemini\config\plugins\prompt-injector' }
$SkipPatch = ($env:KUPADESK_SKIP_PATCH -eq '1')

function Find-NodeExe {
  $cmd = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }
  $candidates = @(
    (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe')
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  $wingetDir = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path -LiteralPath $wingetDir) {
    $hit = Get-ChildItem -Path $wingetDir -Filter 'node.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("kupadesk-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

try {
  Write-Host "[1/4] $(U '5q2j5Zyo6I635Y+WIEt1cGFEZXNrIOacgOaWsOWPkeW4g+a4heWNlQ==') ($BaseUrl)..." -ForegroundColor Cyan
  $manifestUri = "$BaseUrl/manifest.json"
  $envelope = Invoke-RestMethod -Uri $manifestUri -UseBasicParsing -TimeoutSec 25
  if (-not $envelope -or -not $envelope.payload) {
    throw "$(U '5Y+R5biD5riF5Y2V5qC85byP5peg5pWI')"
  }
  $payload = $envelope.payload | ConvertFrom-Json
  $version = [string]$payload.version
  $expectedSha = ([string]$payload.sha256).Trim().ToLowerInvariant()
  $dlRaw = [string]$payload.downloadUrl
  if (-not $version -or -not $expectedSha -or -not $dlRaw) {
    throw "$(U '5Y+R5biD5riF5Y2V57y65bCR54mI5pys44CB5qCh6aqM5ZKM5oiW5LiL6L295Zyw5Z2A')"
  }

  $zipUrl = if ($dlRaw -match '^https?://') { $dlRaw } else { "$BaseUrl/$($dlRaw.TrimStart('/'))" }
  $baseParsed = [Uri]$BaseUrl
  $zipParsed = [Uri]$zipUrl
  if ($zipParsed.Scheme -ne $baseParsed.Scheme -or $zipParsed.Authority -ne $baseParsed.Authority) {
    throw "$(U '5ouS57ud6Z2e5ZCM5rqQ55qE5pu05paw5YyF5LiL6L295Zyw5Z2A'): $zipUrl"
  }

  $zipPath = Join-Path $TempRoot "kupadesk-v$version.zip"
  Write-Host "[2/4] $(U '5q2j5Zyo5LiL6L29') KupaDesk v$version..." -ForegroundColor Cyan
  Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 90

  $sha256Obj = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($zipPath)
    try {
      $actualSha = ([BitConverter]::ToString($sha256Obj.ComputeHash($fs))).Replace('-', '').ToLowerInvariant()
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha256Obj.Dispose()
  }
  if ($actualSha -ne $expectedSha) {
    throw "$(U '5a6J6KOF5YyFIFNIQS0yNTYg5qCh6aqM5aSx6LSl') ($(U '5pyf5pyb'): $expectedSha, $(U '5a6e6ZmF'): $actualSha)"
  }

  Write-Host "[3/4] $(U '5q2j5Zyo5qCh6aqM5bm26Kej5Y6L5a6J6KOF5Yiw') $TargetDir..." -ForegroundColor Cyan
  $extractDir = Join-Path $TempRoot "extracted"
  New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
  $extractFull = [IO.Path]::GetFullPath($extractDir).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    foreach ($entry in $archive.Entries) {
      $rel = ($entry.FullName -replace "\\", "/").TrimStart("/")
      if ([string]::IsNullOrWhiteSpace($rel) -or $rel.EndsWith("/")) { continue }
      if ($rel -match "(^|/)\.\.(/|$)" -or $rel -match "^[A-Za-z]:") {
        throw "$(U '5ouS57ud5YyF5ZCr6Z2e5rOV6Lev5b6E55qE5Y6L57yp5YyF5p2h55uu'): $rel"
      }
      $lower = $rel.ToLowerInvariant()
      if ($rel -eq "rules/AGENTS.md" -or $lower.StartsWith("scripts/") -or $lower.StartsWith(".git/") -or $lower.StartsWith("node_modules/") -or $lower.EndsWith(".pem") -or $lower.EndsWith(".key")) {
        throw "$(U '5ouS57ud5YyF5ZCr56aB5q2i5oiW5pWP5oSf6Lev5b6E55qE5Y6L57yp5YyF5p2h55uu'): $rel"
      }
      $destFile = [IO.Path]::GetFullPath((Join-Path $extractDir ($rel -replace "/", "\")))
      if (-not $destFile.StartsWith($extractFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$(U '5Y6L57yp5YyF5p2h55uu6LaK55WM'): $rel"
      }
      $destParent = [IO.Path]::GetDirectoryName($destFile)
      if (-not (Test-Path -LiteralPath $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
      }
      $inStream = $entry.Open()
      try {
        $outStream = [IO.File]::Create($destFile)
        try {
          $inStream.CopyTo($outStream)
        } finally {
          $outStream.Dispose()
        }
      } finally {
        $inStream.Dispose()
      }
    }
  } finally {
    $archive.Dispose()
  }

  if (-not (Test-Path -LiteralPath (Join-Path $extractDir "plugin.json"))) {
    throw "$(U '6Kej5Y6L5ZCO57y65bCRIHBsdWdpbi5qc29u77yM5Lit5q2i5a6J6KOF')"
  }

  $savedRule = $null
  $existingRule = Join-Path $TargetDir "rules\AGENTS.md"
  if (Test-Path -LiteralPath $existingRule) {
    $savedRule = Join-Path $TempRoot "saved-AGENTS.md"
    Copy-Item -LiteralPath $existingRule -Destination $savedRule -Force
  }

  $backupDir = Join-Path $TempRoot "backup-old"
  if (Test-Path -LiteralPath $TargetDir) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Get-ChildItem -LiteralPath $TargetDir -Force -ErrorAction SilentlyContinue | Move-Item -Destination $backupDir -Force
  } else {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
  }

  try {
    Get-ChildItem -LiteralPath $extractDir -Force | Copy-Item -Destination $TargetDir -Recurse -Force
    if ($savedRule -and (Test-Path -LiteralPath $savedRule)) {
      $rulesDir = Join-Path $TargetDir "rules"
      New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
      Copy-Item -LiteralPath $savedRule -Destination (Join-Path $rulesDir "AGENTS.md") -Force
    }
  } catch {
    if (Test-Path -LiteralPath $backupDir) {
      Get-ChildItem -LiteralPath $TargetDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
      Get-ChildItem -LiteralPath $backupDir -Force -ErrorAction SilentlyContinue | Move-Item -Destination $TargetDir -Force
    }
    throw
  }

  Write-Host "KupaDesk v$version $(U '5o+S5Lu25paH5Lu25bey5oiQ5Yqf5a6J6KOF5Yiw'): $TargetDir" -ForegroundColor Green

  if (-not $SkipPatch) {
    $nodeExe = Find-NodeExe
    $runner = Join-Path $TargetDir "lib\cn-runner.cjs"
    if ($nodeExe -and (Test-Path -LiteralPath $runner)) {
      Write-Host "[4/4] $(U '5q2j5Zyo6YOo572y5Lit5paH5rGJ5YyW44CB5Y+z6ZSu5omT5byA5L2N572u5LiO57qi5qGG5YWl5Y+j5bm26YeN5ZCvIEFudGlncmF2aXR5Li4u')" -ForegroundColor Cyan
      & $nodeExe $runner --action install-all --auto-restart
      if ($LASTEXITCODE -ne 0) {
        Write-Warning "$(U '5a6i5oi356uv6Ieq5Yqo5oyC6L296L+U5Zue6Z2e6Zu254q25oCB') ($LASTEXITCODE)$(U '77yM6K+35omT5byAIEFudGlncmF2aXR5IOWQjuWcqCBLdXBhRGVzayDlj7Pkvqforr7nva7pobXngrnjgIzkuIDplK7lhajlpZflronoo4UgLyDljYfnuqfmgaLlpI3jgI3jgII=')"
      }
    } else {
      Write-Host "[4/4] $(U '5pyq5qOA5rWL5YiwIE5vZGUuanPvvIzot7Pov4foh6rliqjms6jlhaXlrqLmiLfnq6/jgILor7fmiZPlvIAgQW50aWdyYXZpdHnvvIzlnKjmj5Lku7bmiJblj7PkvqcgS3VwYURlc2sg6K6+572u6aG154K55Ye744CM5LiA6ZSu5YWo5aWX5a6J6KOFIC8g5Y2H57qn5oGi5aSN44CN44CC')" -ForegroundColor Yellow
    }
  } else {
    Write-Host "[4/4] $(U '5bey6Lez6L+H5a6i5oi356uv5oyC6L295q2l6aqk') (KUPADESK_SKIP_PATCH=1)." -ForegroundColor DarkGray
  }

  Write-Host "$(U '5YWo6YOo5a6M5oiQ77yB5ZCv5YqoIEFudGlncmF2aXR5IOWQjueCueW8gCBLdXBhRGVzayDorr7nva7pobXovpPlhaXljaHlr4bljbPlj6/kvb/nlKjjgII=')" -ForegroundColor Green
} finally {
  if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
