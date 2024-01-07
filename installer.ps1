param (
  [string]$Version
)

Write-Host 'BUtlerをインストールしています...'
Write-Host

if (-not $Version) {
  Write-Host -NoNewline '最新バージョンを取得しています...'
  try {
    $Version = Invoke-RestMethod -Uri 'https://api.github.com/repos/Per-Terra/butler/releases/latest' | Select-Object -ExpandProperty 'tag_name'
  }
  catch {
    Write-Host ' 失敗'
    Write-Error -Message $_.ToString()
    Write-Host 'Enterキーを押して終了します...'
    Read-Host
    exit 1
  }
  Write-Host " $Version"
}

$zipUrl = "https://github.com/Per-Terra/butler/archive/refs/tags/$Version.zip"
$zipFile = New-TemporaryFile
$extractPath = Join-Path $env:TEMP "butler-$Version"
$installPath = Join-Path -Path (Get-Location) -ChildPath '.butler/'

# 旧インストーラーの残骸を削除
if (Test-Path -LiteralPath (Join-Path -Path $env:TEMP -ChildPath 'butler-main.zip') -PathType Leaf) {
  Remove-Item -LiteralPath (Join-Path -Path $env:TEMP -ChildPath 'butler-main.zip') -Force
}
if (Test-Path -LiteralPath (Join-Path -Path $env:TEMP -ChildPath 'butler-main') -PathType Container) {
  Remove-Item -LiteralPath (Join-Path -Path $env:TEMP -ChildPath 'butler-main') -Recurse -Force
}

if (Test-Path -LiteralPath $installPath -PathType Container) {
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
  $null = New-Item -Path $installPath -ItemType Directory -Force
}

Write-Host -NoNewline 'ファイルをダウンロードしています...'
try {
  Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile
}
catch {
  Write-Error -Message $_.ToString()
  Write-Host ' 失敗'
  Read-Host -Prompt 'Enterキーを押して終了します...'
  exit 1
}
Write-Host ' 完了'

Write-Host -NoNewline 'ファイルを展開しています...'
if (Test-Path -LiteralPath $extractPath -PathType Container) {
  Remove-Item -LiteralPath $extractPath -Recurse -Force
}
Expand-Archive -LiteralPath $zipFile -DestinationPath $extractPath
Write-Host ' 完了'

Write-Host -NoNewline 'ファイルを移動しています...'
Get-ChildItem -Path (Join-Path -Path $extractPath -ChildPath '*/src/*') | ForEach-Object {
  if ($_.Name -eq 'config.yaml' -and (Test-Path -LiteralPath (Join-Path -Path $installPath -ChildPath 'config.yaml') -PathType Leaf)) {
    continue
  }
  if ($_.PSIsContainer -and (Test-Path -LiteralPath (Join-Path -Path $installPath -ChildPath $_.Name) -PathType Container)) {
    Remove-Item -LiteralPath (Join-Path -Path $installPath -ChildPath $_.Name) -Recurse -Force
  }
  Move-Item -LiteralPath $_.FullName -Destination $installPath -Force
}

Write-Host ' 完了'

Write-Host -NoNewline 'ショートカットを作成しています...'
$ShortcutPath = 'BUtler.lnk'
$ShortcutTarget = Join-Path -Path $installPath -ChildPath 'butler.bat'
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $ShortcutTarget
$Shortcut.Save()
Write-Host ' 完了'

Write-Host -NoNewline '一時ファイルを削除しています...'
Remove-Item -LiteralPath $zipFile -Force
Remove-Item -LiteralPath $extractPath -Recurse -Force
Write-Host ' 完了'

Write-Host
Write-Host 'インストールが完了しました'
Start-Sleep -Seconds 3
