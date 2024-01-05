$ZipUrl = 'https://codeload.github.com/Per-Terra/butler/zip/refs/heads/main'
$ZipFileName = 'butler-main.zip'
$ZipFilePath = Join-Path $env:TEMP $ZipFileName
$ExtractPath = Join-Path $env:TEMP 'butler-main'
$InstallPath = Join-Path -Path (Get-Location) -ChildPath '.butler'

Write-Host 'BUtlerをインストールしています...'

if (Test-Path -LiteralPath $InstallPath) {
  Write-Host '.butler フォルダーが既に存在します'
  Write-Host -NoNewline '上書きしますか? [Y/n]'
  do {
    $answer = Read-Host
  } until ([string]::IsNullOrEmpty($answer) -or ($answer -in @('Y', 'n')))
  if ($answer -eq 'n') {
    Write-Host '中断しました'
    exit 0
  }
}

$isZipDownloaded = $false
if (Test-Path -LiteralPath $ZipFilePath) {
  Write-Host 'ZIPアーカイブが既に存在します'
  Write-Host -NoNewline '再ダウンロードしますか? [y/N]'
  do {
    $answer = Read-Host
  } until ([string]::IsNullOrEmpty($answer) -or ($answer -in @('y', 'N')))
  if ($answer -eq 'y') {
    Remove-Item -Path $ZipFilePath -Force
  }
  else {
    $isZipDownloaded = $true
  }
}

if (-not $isZipDownloaded) {
  Write-Host "ファイルをダウンロードしています: $ZipUrl"
  try {
    Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFilePath
  }
  catch {
    Write-Error -Message $_.ToString()
    Write-Host 'ダウンロードに失敗しました'
    exit 1
  }
}

Write-Host 'ファイルを展開しています...'
if (Test-Path -LiteralPath $ExtractPath -PathType Container) {
  Remove-Item -Path $ExtractPath -Recurse -Force
}
Expand-Archive -Path $ZipFilePath -DestinationPath $ExtractPath

Write-Host 'ファイルをコピーしています...'
Get-ChildItem (Join-Path -Path $ExtractPath -ChildPath 'butler-main/src') -Recurse -File |
Copy-Item -Destination $InstallPath -Recurse

Write-Host 'ショートカットを作成しています...'
$ShortcutPath = 'BUtler.lnk'
$ShortcutTarget = Join-Path -Path $InstallPath -ChildPath 'butler.bat'
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $ShortcutTarget
$Shortcut.Save()

Write-Host 'インストールが完了しました'

Start-Sleep -Seconds 3
