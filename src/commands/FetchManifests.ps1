[CmdletBinding()]
param (
  [Parameter(Mandatory = $false)]
  [System.Uri]$BaseUrl = [System.Uri]::new('https://github.com/Per-Terra/butler-pkgs/releases/latest/download/')
)

. (Join-Path -Path $PSScriptRoot -ChildPath '../lib/Get-Sha256.ps1')

$ReleaseUrl = [System.Uri]::new($BaseUrl, './release.yaml')
$CacheDirectory = Join-Path -Path $PSScriptRoot -ChildPath '../cache'
$ManifestsCacheDirectory = Join-Path -Path $CacheDirectory -ChildPath 'manifests'
if (-not (Test-Path -LiteralPath $CacheDirectory -PathType Container)) {
  $null = New-Item -Path $CacheDirectory -ItemType Directory
}
if (-not (Test-Path -LiteralPath $ManifestsCacheDirectory -PathType Container)) {
  $null = New-Item -Path $ManifestsCacheDirectory -ItemType Directory
}

Write-Host "取得中: $ReleaseUrl"

$releasePath = Join-Path -Path $ManifestsCacheDirectory -ChildPath "$($ReleaseUrl.Host)$($ReleaseUrl.AbsolutePath)"
$cachedRelease = $null
if (Test-Path -LiteralPath $releasePath -PathType Leaf) {
  try {
    $cachedRelease = Get-Item -LiteralPath $releasePath | Get-Content -Raw | ConvertFrom-Yaml
  }
  catch {
    Write-Warning -Message "キャッシュの読み込みに失敗しました: $releasePath"
    Write-Warning -Message $_.ToString()
    Write-Warning -Message 'キャッシュを使用せずに続行します'
  }
}
elseif (-not (Test-Path -LiteralPath (Split-Path -Path $releasePath -Parent) -PathType Container)) {
  $null = New-Item -Path (Split-Path -Path $releasePath -Parent) -ItemType Directory
}

try {
  $release = Invoke-WebRequest -Uri $ReleaseUrl -OutFile $releasePath -PassThru | ConvertFrom-Yaml
}
catch {
  Write-Error -Message "リリースの取得に失敗しました: $ReleaseUrl"
  Write-Error -Message $_.ToString()
  exit 1
}

$isCacheAvailable = $null

if ($cachedRelease -and ([datetime]$cachedRelease.Date -ge [datetime]$release.Date)) {
  $release.Files | ForEach-Object {
    $cachedFilePath = Join-Path -Path (Split-Path -Path $releasePath -Parent) -ChildPath $_.Name
    if (Test-Path -LiteralPath $cachedFilePath) {
      $sha256 = $cachedFilePath | Get-Sha256
      if ($sha256 -eq $_.Sha256) {
        $isCacheAvailable = $true
      }
      else {
        Write-Debug -Message "ファイルのハッシュ値が一致しません: $cachedFilePath"
        $isCacheAvailable = $false
      }
    }
    else {
      Write-Debug -Message "ファイルが存在しません: $cachedFilePath"
      $isCacheAvailable = $false
    }
  }
}
else {
  $isCacheAvailable = $false
  Get-ChildItem -LiteralPath (Split-Path -Path $releasePath -Parent) -Exclude 'release.yaml' -Recurse | Remove-Item -Force -Recurse
}

if ($isCacheAvailable) {
  Write-Host 'パッケージマニフェストは最新の状態です'
  exit 0
}
else {
  $files = @{}
  $release.Files | ForEach-Object {
    $fileUrl = [System.Uri]::new($BaseUrl, $_.Name)
    $cacheFilePath = Join-Path -Path (Split-Path -Path $releasePath -Parent) -ChildPath $_.Name
    try {
      $file = (Invoke-WebRequest -Uri $fileUrl -OutFile $cacheFilePath -PassThru).Content
    }
    catch {
      Write-Error -Message "ファイルの取得に失敗しました: $fileUrl"
      Write-Error -Message $_.ToString()
      exit 1
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $sha256Bytes = $sha256.ComputeHash($file)
    $sha256String = [System.BitConverter]::ToString($sha256Bytes).Replace('-', '').ToLower()
    if ($sha256String -ne $_.Sha256) {
      Write-Error -Message "ファイルのハッシュ値が一致しません: $fileUrl"
      exit 1
    }
    $files.Add($_.Name, $file)
  }
}

$files.GetEnumerator() | ForEach-Object {
  if ($_.Key.EndsWith('.gz')) {
    $filePath = Join-Path -Path (Split-Path -Path $releasePath -Parent) -ChildPath $_.Key.Replace('.gz', '')
    $stream = [System.IO.Compression.GZipStream]::new([System.IO.MemoryStream]::new($_.Value), [System.IO.Compression.CompressionMode]::Decompress)
    $stream.CopyTo([System.IO.FileStream]::new($filePath, [System.IO.FileMode]::Create))
    $stream.Close()
  }
}

Write-Host 'パッケージマニフェストの更新が完了しました'
