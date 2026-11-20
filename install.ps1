$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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
  Write-Host "[1/4] 正在获取 KupaDesk 最新发布清单 ($BaseUrl)..." -ForegroundColor Cyan
  $manifestUri = "$BaseUrl/manifest.json"
  $envelope = Invoke-RestMethod -Uri $manifestUri -UseBasicParsing -TimeoutSec 25
  if (-not $envelope -or -not $envelope.payload) {
    throw "发布清单格式无效"
  }
  $payload = $envelope.payload | ConvertFrom-Json
  $version = [string]$payload.version
  $expectedSha = ([string]$payload.sha256).Trim().ToLowerInvariant()
  $dlRaw = [string]$payload.downloadUrl
  if (-not $version -or -not $expectedSha -or -not $dlRaw) {
    throw "发布清单缺少版本、校验和或下载地址"
  }

  $zipUrl = if ($dlRaw -match '^https?://') { $dlRaw } else { "$BaseUrl/$($dlRaw.TrimStart('/'))" }
  $baseParsed = [Uri]$BaseUrl
  $zipParsed = [Uri]$zipUrl
  if ($zipParsed.Scheme -ne $baseParsed.Scheme -or $zipParsed.Authority -ne $baseParsed.Authority) {
    throw "拒绝非同源的更新包下载地址: $zipUrl"
  }

  $zipPath = Join-Path $TempRoot "kupadesk-v$version.zip"
  Write-Host "[2/4] 正在下载 KupaDesk v$version..." -ForegroundColor Cyan
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
    throw "安装包 SHA-256 校验失败 (期望: $expectedSha, 实际: $actualSha)"
  }

  Write-Host "[3/4] 正在校验并解压安装到 $TargetDir..." -ForegroundColor Cyan
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
        throw "拒绝包含非法路径的压缩包条目: $rel"
      }
      $lower = $rel.ToLowerInvariant()
      if ($rel -eq "rules/AGENTS.md" -or $lower.StartsWith("scripts/") -or $lower.StartsWith(".git/") -or $lower.StartsWith("node_modules/") -or $lower.EndsWith(".pem") -or $lower.EndsWith(".key")) {
        throw "拒绝包含禁止或敏感路径的压缩包条目: $rel"
      }
      $destFile = [IO.Path]::GetFullPath((Join-Path $extractDir ($rel -replace "/", "\")))
      if (-not $destFile.StartsWith($extractFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "压缩包条目越界: $rel"
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
    throw "解压后缺少 plugin.json，中止安装"
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

  Write-Host "KupaDesk v$version 插件文件已成功安装到: $TargetDir" -ForegroundColor Green

  if (-not $SkipPatch) {
    $nodeExe = Find-NodeExe
    $runner = Join-Path $TargetDir "lib\cn-runner.cjs"
    if ($nodeExe -and (Test-Path -LiteralPath $runner)) {
      Write-Host "[4/4] 正在部署中文汉化、右键打开位置与红框入口并重启 Antigravity..." -ForegroundColor Cyan
      & $nodeExe $runner --action install-all --auto-restart
      if ($LASTEXITCODE -ne 0) {
        Write-Warning "客户端自动挂载返回非零状态 ($LASTEXITCODE)，请打开 Antigravity 后在 KupaDesk 右侧设置页点「一键全套安装 / 升级恢复」。"
      }
    } else {
      Write-Host "[4/4] 未检测到 Node.js，跳过自动注入客户端。请打开 Antigravity，在插件或右侧 KupaDesk 设置页点击「一键全套安装 / 升级恢复」。" -ForegroundColor Yellow
    }
  } else {
    Write-Host "[4/4] 已跳过客户端挂载步骤 (KUPADESK_SKIP_PATCH=1)。" -ForegroundColor DarkGray
  }

  Write-Host "全部完成！启动 Antigravity 后点开 KupaDesk 设置页输入卡密即可使用。" -ForegroundColor Green
} finally {
  if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
