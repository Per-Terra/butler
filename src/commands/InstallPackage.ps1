[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [string]$Identifier,
  [Parameter(Mandatory = $true)]
  [string]$Version,
  [Parameter(Mandatory = $true)]
  [pscustomobject]$Manifest,
  [Parameter(Mandatory = $true)]
  [string]$RootDirectory,
  [Parameter(Mandatory = $true)]
  [string]$CacheDirectory,
  [Parameter(Mandatory = $true)]
  [string]$PackageDirectory,
  [Parameter(Mandatory = $true)]
  [string]$ManagedFilesPath,
  [Parameter(Mandatory = $false)]
  [switch]$NoSymbolicLink
)

# Remove-Itemの進捗状況バーが消えない問題に対するワークアラウンド
# ref: https://github.com/PowerShell/PowerShell/issues/23875
$PSDefaultParameterValues['Remove-Item:ProgressAction'] = 'SilentlyContinue'

Write-Host "$Identifier ($Version) をインストールしています..."

. (Join-Path -Path $PSScriptRoot -ChildPath '../lib/Get-Sha256.ps1')

$script:managedFiles = @(Import-Csv -LiteralPath $ManagedFilesPath)
# 型アサーション
$script:managedFiles | ForEach-Object {
  $_.IsConfFile = [bool]::Parse($_.IsConfFile)
}

if (-not $Manifest.Files) {
  return
}

function Install-File {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [string]$Sha256,
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Install
  )

  if (-not $Install.Strict -and ($Install.TargetPath -match '^script/([^/]*)$')) {
    $Install.TargetPath = "script/$($Manifest.Developer[0])/$($Matches[1])"
  }
  $targetPath = Join-Path -Path $RootDirectory -ChildPath $Install.TargetPath

  if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
    Write-Debug "ファイルが既に存在します: $targetPath"
    $managedFileInfo = $script:managedFiles | Where-Object { $_.Path -eq $Install.TargetPath }
    if ($managedFileInfo) {
      if ($managedFileInfo.IsConfFile) {
        Write-Debug "ファイルは設定ファイルです: $targetPath"
        Write-Debug "スキップしました"
        return
      }
      if ($managedFileInfo.Identifier -eq $Identifier -or ($managedFileInfo.Identifier -in $Manifest.Replaces)) {
        Write-Debug "ファイルを削除しています: $targetPath"
        Remove-Item -LiteralPath $targetPath -Force
        $script:managedFiles = $script:managedFiles | Where-Object { $_.Path -ne $Install.TargetPath }
      }
      else {
        Write-Host -ForegroundColor Yellow "ファイルは既に $($managedFileInfo.Identifier) ($($managedFileInfo.Version)) によってインストールされています: $targetPath"
        Write-Host -ForegroundColor Yellow 'スキップしました'
      }
    }
    else {
      Write-Host -ForegroundColor Yellow "ファイルが既に存在します: $targetPath"
      Write-Host -ForegroundColor Yellow 'ファイルは手動でインストールされた可能性があります'
      Write-Host -NoNewline 'ファイルを上書きしますか? [y/N]'
      do {
        $answer = Read-Host
      } until ([string]::IsNullOrEmpty($answer) -or ($answer -in @('y', 'N')))
      if ($answer -eq 'y') {
        Write-Debug "ファイルを削除しています: $targetPath"
        Remove-Item -LiteralPath $targetPath -Force
      }
      else {
        Write-Host 'スキップしました'
        return
      }
    }
  }

  if (-not (Test-Path -LiteralPath (Split-Path -Path $targetPath -Parent) -PathType Container)) {
    $null = New-Item -Path (Split-Path -Path $targetPath -Parent) -ItemType Directory
  }
  if ($NoSymbolicLink -or ($Install.Method -eq 'Copy') -or $Install.ConfFile) {
    Write-Debug "ファイルをコピーしています: $targetPath"
    $null = Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Force
  }
  else {
    Write-Debug "シンボリックリンクを作成しています: $targetPath"
    $null = New-Item -Path $targetPath -ItemType SymbolicLink -Value (Resolve-Path -LiteralPath $SourcePath -Relative -RelativeBasePath (Split-Path -Path $targetPath -Parent)) -Force
  }

  $script:managedFiles += [pscustomobject]@{
    Path       = $Install.TargetPath
    Sha256     = $Sha256
    Identifier = $Identifier
    Version    = $Version
    IsConfFile = [bool]$Install.ConfFile
  }
}

function Install-Archive {
  param (
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Files
  )

  $expandDirectory = Join-Path -Path $PackageDirectory -ChildPath (Split-Path -Path $SourcePath -Leaf)

  if (Test-Path -LiteralPath $expandDirectory -PathType Container) {
    Write-Debug "展開済みのアーカイブが存在します: $expandDirectory"
    try {
      Remove-Item -LiteralPath $expandDirectory -Force -Recurse
    }
    catch {
      Write-Error "ディレクトリの削除に失敗しました: $expandDirectory"
      throw
    }
  }

  try {
    Expand-7Zip -ArchiveFileName $SourcePath -TargetPath $expandDirectory
  }
  catch {
    Write-Error "アーカイブの展開に失敗しました: $SourcePath"
    throw
  }

  foreach ($file in $Files) {
    $sourcePath = Join-Path -Path $expandDirectory -ChildPath $file.Path
    $sha256 = $sourcePath | Get-Sha256
    if ($sha256 -ne $file.Sha256) {
      Write-Error "ファイルのハッシュ値が一致しません: $sourcePath"
      throw
    }
    if ($file.Files) {
      Install-Archive -SourcePath $sourcePath -Files $file.Files
    }
    elseif ($file.Install) {
      Install-File -SourcePath $sourcePath -Sha256 $sha256 -Install $file.Install
    }
  }
}

foreach ($sourceFile in $Manifest.Files) {
  $sourceUrl = [System.Uri]::new($sourceFile.SourceUrl)
  $isCacheAvailable = $null
  $cacheFilePath = Join-Path -Path $CacheDirectory -ChildPath "$($sourceUrl.Host)$($sourceUrl.AbsolutePath)"
  if ($sourceFile.FileName) {
    $cacheFilePath = Join-Path -Path $cacheFilePath -ChildPath $sourceFile.FileName
  }
  if (-not (Test-Path -LiteralPath (Split-Path -Path $cacheFilePath -Parent) -PathType Container)) {
    $null = New-Item -Path (Split-Path -Path $cacheFilePath -Parent) -ItemType Directory
  }
  if (Test-Path -LiteralPath $cacheFilePath -PathType Leaf) {
    $sha256 = $cacheFilePath | Get-Sha256
    if ($sha256 -eq $sourceFile.Sha256) {
      $isCacheAvailable = $true
    }
    else {
      Write-Debug "ファイルのハッシュ値が一致しません: $cacheFilePath"
      $isCacheAvailable = $false
    }
  }
  else {
    Write-Debug "キャッシュが存在しません: $cacheFilePath"
  }

  if (-not $isCacheAvailable) {
    $params = @{
      Uri     = $sourceUrl
      OutFile = $cacheFilePath
    }

    # rikky氏のAmazonっぽいからのダウンロードに対応
    if ($sourceUrl -match 'https://hazumurhythm\.com/php/amazon_download\.php\?name=(.+)') {
      $id = $Matches[1]
      $params.Add('Headers', @{ Referer = "https://hazumurhythm.com/wev/amazon/?script=$id" })
    }

    try {
      Write-Debug "ファイルをダウンロードしています: $($sourceUrl.AbsoluteUri)"
      Invoke-WebRequest @params
    }
    catch {
      Write-Error $_.ToString()
      Write-Error "ファイルのダウンロードに失敗しました: $($sourceUrl.AbsoluteUri)"
      throw
    }

    $sha256 = $cacheFilePath | Get-Sha256
    if ($sha256 -ne $sourceFile.Sha256) {
      Write-Error "ファイルのハッシュ値が一致しません: $cacheFilePath"
      throw
    }
  }

  if ($sourceFile.Files) {
    Install-Archive -SourcePath $cacheFilePath -Files $sourceFile.Files
  }
  elseif ($sourceFile.Install) {
    $sourcePath = Join-Path -Path $PackageDirectory -ChildPath (Split-Path -Path $cacheFilePath -Leaf)
    Copy-Item -LiteralPath $cacheFilePath -Destination $sourcePath -Force
    Install-File -SourcePath $sourcePath -Sha256 $sha256 -Install $sourceFile.Install
  }
}

try {
  (($script:managedFiles | ConvertTo-Csv -NoTypeInformation -QuoteFields 'Path') -join "`n") + "`n" | Set-Content -LiteralPath $ManagedFilesPath -Force -NoNewline
}
catch {
  Write-Error "ファイルの書き込みに失敗しました: $ManagedFilesPath"
  throw
}
