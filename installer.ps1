$ZipUrl = 'https://codeload.github.com/Per-Terra/butler/zip/refs/heads/main'
$ZipFIle = New-TemporaryFile
$ExtractPath = Join-Path $env:TEMP 'butler-main/'
$InstallPath = Join-Path -Path (Get-Location) -ChildPath '.butler/'

# 旧インストーラーの残骸を削除
if (Test-Path -LiteralPath (Join-Path -Path $env:TEMP -ChildPath 'butler-main.zip') -PathType Leaf) {
  Remove-Item -Path (Join-Path -Path $env:TEMP -ChildPath 'butler-main.zip') -Force
}

Write-Host 'BUtlerをインストールしています...'
Write-Host

if (Test-Path -LiteralPath $InstallPath -PathType Container) {
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
else {
  $null = New-Item -Path $InstallPath -ItemType Directory -Force
}

Write-Host -NoNewline 'ファイルをダウンロードしています...'
try {
  Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFIle
}
catch {
  Write-Error -Message $_.ToString()
  Write-Host ' 失敗'
  Start-Sleep -Seconds 5
  exit 1
}
Write-Host ' 完了'

Write-Host -NoNewline 'ファイルを展開しています...'
if (Test-Path -LiteralPath $ExtractPath -PathType Container) {
  Remove-Item -Path $ExtractPath -Recurse -Force
}
Expand-Archive -Path $ZipFIle -DestinationPath $ExtractPath
Write-Host ' 完了'

Write-Host -NoNewline 'ファイルをコピーしています...'
Copy-Item -Path (Join-Path -Path $ExtractPath -ChildPath 'butler-main/src/*') -Destination $InstallPath -Recurse -Force
Write-Host ' 完了'

Write-Host -NoNewline 'ショートカットを作成しています...'
$ShortcutPath = 'BUtler.lnk'
$ShortcutTarget = Join-Path -Path $InstallPath -ChildPath 'butler.bat'
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $ShortcutTarget
$Shortcut.Save()
Write-Host ' 完了'

Write-Host -NoNewline 'ファイルを削除しています...'
Remove-Item -Path $ZipFIle -Force
Remove-Item -Path $ExtractPath -Recurse -Force
Write-Host ' 完了'

Write-Host
Write-Host 'インストールが完了しました'

Start-Sleep -Seconds 3
