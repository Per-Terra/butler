[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [string]$Identifier,
  [Parameter(Mandatory = $false)]
  [string]$Version,
  [Parameter(Mandatory = $true)]
  [pscustomobject]$Manifest,
  [Parameter(Mandatory = $true)]
  [string]$RootDirectory,
  [Parameter(Mandatory = $true)]
  [string]$PackageDirectory,
  [Parameter(Mandatory = $true)]
  [string]$ManagedFilesPath,
  [Parameter(Mandatory = $false)]
  [switch]$Purge
)

if ($Purge) {
  Write-Host "$Identifier ($Version) を完全に削除しています..."
}
else {
  Write-Host "$Identifier ($Version) を削除しています..."
}

. (Join-Path -Path $PSScriptRoot -ChildPath '../lib/Get-Sha256.ps1')

$managedFiles = @(Import-Csv -LiteralPath $ManagedFilesPath)
$filesToRemove = $managedFiles | Where-Object { $_.Identifier -eq $Identifier }

foreach ($fileToRemove in $filesToRemove) {
  $path = Join-Path -Path $RootDirectory -ChildPath $fileToRemove.Path
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    if ($Purge -or (-not $fileToRemove.IsConfFile)) {
      Write-Debug -Message "ファイルを削除しています: $path"
      Remove-Item -LiteralPath $path -Force
    }
    else {
      $sha256 = $path | Get-Sha256
      if ($sha256 -eq $fileToRemove.Sha256) {
        Write-Debug -Message "ファイルを削除しています: $path"
        Remove-Item -LiteralPath $path -Force
      }
      else {
        Write-Debug -Message "ファイルは変更されています: $path"
        continue
      }
    }
  }
  else {
    Write-Debug -Message "ファイルが存在しません: $path"
  }
  $managedFiles = $managedFiles | Where-Object { $_.Path -ne $fileToRemove.Path }
}

if ($Purge) {
  if ($Manifest.ConfFiles) {
    foreach ($confFile in $Manifest.ConfFiles) {
      $path = Join-Path -Path $RootDirectory -ChildPath $confFile
      if (Test-Path -LiteralPath $path -PathType Leaf) {
        Write-Debug -Message "ファイルを削除しています: $path"
        Remove-Item -LiteralPath $path -Force
      }
      else {
        Write-Debug -Message "ファイルが存在しません: $path"
      }
    }
  }
}

if (Test-Path -LiteralPath $PackageDirectory -PathType Container) {
  try {
    Remove-Item -LiteralPath $PackageDirectory -Force -Recurse
  }
  catch {
    Write-Error -Message "ディレクトリの削除に失敗しました: $PackageDirectory"
  }
}

Write-Debug -Message "空のディレクトリを削除しています: $RootDirectory"
Get-ChildItem -LiteralPath $RootDirectory -Directory -Recurse -Force | Sort-Object -Descending | ForEach-Object {
  if ((Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0) {
    try {
      Remove-Item -LiteralPath $_.FullName -Force
    }
    catch {
      Write-Error -Message "ディレクトリの削除に失敗しました: $($_.FullName)"
    }
  }
}

try {
  (($managedFiles | ConvertTo-Csv -NoTypeInformation -QuoteFields 'Path') -join "`n") + "`n" | Set-Content -LiteralPath $ManagedFilesPath -Force -NoNewline
}
catch {
  Write-Error -Message "ファイルの書き込みに失敗しました: $ManagedFilesPath"
}
