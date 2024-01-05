#Requires -Version 7.4
[CmdletBinding()]

$ScriptVersion = '0.1.0'

$Commands = [ordered]@{
  help        = @{
    Key         = 'help'
    Description = 'ヘルプを表示する (このコマンド)'
  }
  list        = @{
    Key         = 'list'
    Description = 'インストールされているパッケージを一覧表示する'
  }
  search      = @{
    Key         = 'search'
    Description = 'パッケージを検索する'
  }
  show        = @{
    Key         = 'show'
    Description = 'パッケージの詳細を表示する'
  }
  install     = @{
    Key         = 'install'
    Description = 'パッケージをインストールする'
  }
  reinstall   = @{
    Key         = 'reinstall'
    Description = 'パッケージを再インストールする'
  }
  remove      = @{
    Key         = 'remove'
    Description = 'パッケージを削除する'
  }
  purge       = @{
    Key         = 'purge'
    Description = 'パッケージを完全に削除する'
  }
  autoremove  = @{
    Key         = 'autoremove'
    Description = '自動でインストールされたがもはや使われていないパッケージを削除する'
  }
  autopurge   = @{
    Key         = 'autopurge'
    Description = '自動でインストールされたがもはや使われていないパッケージを完全に削除する'
  }
  update      = @{
    Key         = 'update'
    Description = 'パッケージマニフェストを更新する'
  }
  upgrade     = @{
    Key         = 'upgrade'
    Description = 'パッケージをアップグレードする'
  }
  interactive = @{
    Key         = 'interactive'
    Description = '対話型シェルモードで実行する'
  }
}

if ($args[0] -is [array]) {
  $args = $args[0]
}

$Command = $args[0]
if (-not $Command) {
  $Command = $Commands.interactive.Key
}

if ($Command -eq $Commands.interactive.Key) {
  Write-Host "BUtler $ScriptVersion Interactive Mode"
  Write-Host
  Write-Host 'help で使用方法を表示します'
  Write-Host '終了する場合は exit と入力するか、Ctrl+C を押してください'
  $exit = $false
  do {
    Write-Host
    Write-Host -ForegroundColor Green -NoNewline 'BUtler'
    Write-Host -NoNewline '> '
    $input = Read-Host
    $input = $input.Trim()
    if ($input -eq 'exit') {
      $exit = $true
    }
    elseif ($input) {
      $input = $input.Split(' ')
      try {
        . $MyInvocation.MyCommand.Path $input
      }
      catch {
        Write-Host -ForegroundColor Red $_.ToString()
      }
    }
  } until ($exit)
  exit 0
}

if ($Command -eq $Commands.help.Key) {
  Write-Host "BUtler $ScriptVersion"
  Write-Host '使用方法: .\butler.ps1 <コマンド>'
  Write-Host
  Write-Host 'BUtlerはAviUtl用のコマンドラインパッケージマネージャーです。'
  Write-Host
  Write-Host 'コマンド:'
  $Commands.GetEnumerator() | ForEach-Object {
    Write-Host "  $($_.Value.Key)$(' ' * (11 - $_.Value.Key.Length)) - $($_.Value.Description)"
  }
  Write-Host
  Write-Host '詳細は https://github.com/Per-Terra/butler をご覧ください。'
  exit 0
}

if ($Command -notin $Commands.Values.Key) {
  Write-Host -ForegroundColor Red "コマンドが見つかりません: $Command"
  Write-Host -ForegroundColor Red '使用方法: .\butler.ps1 <コマンド>'
  exit 1
}

### original: https://github.com/microsoft/winget-pkgs/blob/4e76aed0d59412f0be0ecfefabfa14b5df05bec4/Tools/YamlCreate.ps1#L135-L149
# 必要なモジュールのインストール
$scriptDependencies = @('7Zip4Powershell', 'powershell-yaml')
$scriptDependencies | ForEach-Object {
  if (-not(Get-Module -ListAvailable -Name $_)) {
    try {
      Install-Module -Name $_ -Force -Repository PSGallery -Scope CurrentUser
    }
    catch {
      throw "'$_' のインストールに失敗しました"
    }
    finally {
      # Double check that it was installed properly
      if (-not(Get-Module -ListAvailable -Name $_)) {
        throw "'$_' が見つかりません"
      }
    }
  }
}
###

. (Join-Path -Path $PSScriptRoot -ChildPath './lib/Get-Sha256.ps1')

$ConsoleWidth = $Host.UI.RawUI.BufferSize.Width

$RootDirectory = Split-Path -Path $PSScriptRoot -Parent
$SourcesPath = Join-Path -Path $PSScriptRoot -ChildPath 'sources.yaml'
$ManagedFilesPath = Join-Path -Path $PSScriptRoot -ChildPath 'files.csv'
$managedPackagesPath = Join-Path -Path $PSScriptRoot -ChildPath 'packages.csv'
$PackagesDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'packages'
$CacheDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'cache'
$ManifestsCacheDirectory = Join-Path -Path $CacheDirectory -ChildPath 'manifests'
$PackagesCacheDirectory = Join-Path -Path $CacheDirectory -ChildPath 'packages'

if (-not (Test-Path -Path $SourcesPath)) {
  Write-Host -ForegroundColor Red "$SourcesPath が見つかりません"
  exit 1
}

@(
  $CacheDirectory
  $ManifestsCacheDirectory
  $PackagesCacheDirectory
) | ForEach-Object {
  if (-not (Test-Path -Path $_ -PathType Container)) {
    $null = New-Item -Path $_ -ItemType Directory
  }
}

try {
  $SourceUrls = [System.Uri[]](Get-Content -Path $SourcesPath -Raw | ConvertFrom-Yaml)
}
catch {
  Write-Error -Message $_.ToString()
  exit 1
}

$SourceUrls | ForEach-Object {
  if (-not $_.IsWellFormedOriginalString()) {
    Write-Host -ForegroundColor Red "URLの形式が正しくありません: $($_.OriginalString)"
    Write-Host -ForegroundColor Red 'sources.yaml が正しく設定されていることを確認してください'
    exit 1
  }
  if (-not ($_.Scheme -eq 'http' -or $_.Scheme -eq 'https')) {
    Write-Host -ForegroundColor Red "スキームがhttpまたはhttpsではありません: $($_.OriginalString)"
    Write-Host -ForegroundColor Red 'sources.yaml が正しく設定されていることを確認してください'
    exit 1
  }
}

try {
  if (-not (Test-Path -Path $managedPackagesPath)) {
    $null = New-Item -Path $managedPackagesPath -ItemType File
  }
  $script:managedPackages = @(Import-Csv -LiteralPath $managedPackagesPath)
}
catch {
  Write-Error -Message $_.ToString()
  exit 1
}

if ($Command -eq $Commands.update.Key) {
  $SourceUrls | ForEach-Object {
    & (Join-Path -Path $PSScriptRoot -ChildPath './commands/FetchManifests.ps1') -BaseUrl $_
  }
  $PackageManifests = $null
}

if (-not $PackageManifests) {
  Write-Host -NoNewline 'パッケージを読み込んでいます...'

  $PackageManifests = @{}

  $SourceUrls | ForEach-Object {
    $releaseUrl = [System.Uri]::new($_, './release.yaml')
    $releasePath = Join-Path -Path $ManifestsCacheDirectory -ChildPath "$($releaseUrl.Host)$($releaseUrl.AbsolutePath)"
    if (Test-Path -Path $releasePath) {
      try {
        $release = Get-Item -Path $releasePath | Get-Content -Raw | ConvertFrom-Yaml
      }
      catch {
        Write-Error -Message $_.ToString()
        Write-Host -ForegroundColor Red ' 失敗'
        Write-Host -ForegroundColor Red "release.yaml を読み込めません: $releasePath"
        Write-Host -ForegroundColor Red 'update コマンドを実行してから再度お試しください'
        exit 1
      }
      $release.Files | ForEach-Object {
        $filePath = Join-Path -Path (Split-Path -Path $releasePath -Parent) -ChildPath $_.Name
        if ($filePath.EndsWith('.gz')) { $filePath = $filePath -replace '\.gz$', '' }
        try {
          $file = Get-Content -LiteralPath $filePath -Raw | ConvertFrom-Json
        }
        catch {
          Write-Host -ForegroundColor Red ' 失敗'
          Write-Error -Message $_.ToString()
          Write-Host -ForegroundColor Red "ファイルを読み込めません: $filePath"
          Write-Host -ForegroundColor Red 'update コマンドを実行してから再度お試しください'
          exit 1
        }
        if (-not $file) {
          Write-Host -ForegroundColor Red ' 失敗'
          Write-Error -Message $_.ToString()
          Write-Host -ForegroundColor Red "ファイルを読み込めません: $filePath"
          Write-Host -ForegroundColor Red 'update コマンドを実行してから再度お試しください'
          exit 1
        }
        $file.Packages.psobject.Properties | ForEach-Object {
          if ($PackageManifests.ContainsKey($_.Name)) {
            $PackageManifests[$_.Name].Add($_.Value)
          }
          else {
            $PackageManifests.Add($_.Name, $_.Value)
          }
        }
      }
    }
    else {
      Write-Host -ForegroundColor Red ' 失敗'
      Write-Error -Message $_.ToString()
      Write-Host -ForegroundColor Red "release.yaml が見つかりません: $releasePath"
      Write-Host -ForegroundColor Red 'update コマンドを実行してから再度お試しください'
      exit 1
    }
  }
  Write-Host ' 完了'
}

if ($Command -eq $Commands.list.Key) {
  $script:managedPackages | Where-Object { $_.Status -eq 'Installed' } | ForEach-Object {
    $packageIdentifier = $_.Identifier
    $packageVersion = $_.Version
    $manifest = $PackageManifests.$packageIdentifier.$packageVersion
    [PSCustomObject]@{
      Identifier  = $packageIdentifier
      Version     = $packageVersion
      ReleaseDate = $manifest.ReleaseDate
      Developer   = $manifest.Developer -join ', '
      Section     = $manifest.Section
      DisplayName = $manifest.DisplayName
      Description = $manifest.Description
    }
  } |
  Sort-Object -Property Identifier |
  Format-Table -AutoSize

  exit 0
}

if ($Command -eq $Commands.search.Key) {
  if ($args.Count -lt 2) {
    Write-Host -ForegroundColor Red '検索クエリが指定されていません'
    Write-Host -ForegroundColor Red '使い方: .\butler.ps1 search <検索クエリ>'
    exit 1
  }
  elseif ($args.Count -gt 2) {
    Write-Host -ForegroundColor Red '検索クエリが複数指定されています'
    Write-Host -ForegroundColor Red '使い方: .\butler.ps1 search <検索クエリ>'
    exit 1
  }
  $query = $args[1]

  $PackageManifests.GetEnumerator() |
  Where-Object { $_.Key -like "*$query*" -or
  (($_.Value.psobject.Properties | Select-Object -First 1 -ExpandProperty Value).DisplayName -like "*$query*") -or
  (($_.Value.psobject.Properties | Select-Object -First 1 -ExpandProperty Value).Description -like "*$query*")
  } |
  ForEach-Object {
    $latestPackageVersion = $_.Value.psobject.Properties | Select-Object -First 1 -ExpandProperty Name
    $manifest = $_.Value.$latestPackageVersion
    [PSCustomObject]@{
      Identifier  = $_.Key
      Version     = $latestPackageVersion
      ReleaseDate = $manifest.ReleaseDate
      Developer   = $manifest.Developer -join ', '
      Section     = $manifest.Section
      DisplayName = $manifest.DisplayName
      Description = $manifest.Description
    }
  } |
  Sort-Object -Property Identifier |
  Format-Table -AutoSize

  exit 0
}

if ($Command -eq $Commands.show.Key) {
  if ($args.Count -lt 2) {
    Write-Host -ForegroundColor Red 'パッケージ名が指定されていません'
    Write-Host -ForegroundColor Red '使い方: .\butler.ps1 show <パッケージ名>[=<バージョン>]'
    exit 1
  }
  elseif ($args.Count -gt 2) {
    Write-Host -ForegroundColor Red 'パッケージ名が複数指定されています'
    Write-Host -ForegroundColor Red '使い方: .\butler.ps1 show <パッケージ名>[=<バージョン>]'
    exit 1
  }
  $packageIdentifier = $args[1]
  $packageVersion = $null
  if ($packageIdentifier.Contains('=')) {
    $packageIdentifier, $packageVersion = $packageIdentifier.Split('=')
  }

  if (-not $PackageManifests.ContainsKey($packageIdentifier)) {
    Write-Host -ForegroundColor Red "パッケージが見つかりません: $packageIdentifier"
    exit 1
  }
  $package = $PackageManifests.GetEnumerator() | Where-Object { $_.Key -eq $packageIdentifier } | Select-Object -First 1
  $packageIdentifier = $package.Key
  if ($packageVersion) {
    $packageVersion = $package.Value.psobject.Properties | Where-Object { $_.Name -eq $packageVersion } | Select-Object -First 1 -ExpandProperty Name
    if (-not $packageVersion) {
      Write-Host -ForegroundColor Red "バージョンが見つかりません: $packageIdentifier"
      exit 1
    }
  }
  else {
    $packageVersion = $package.Value.psobject.Properties | Select-Object -First 1 -ExpandProperty Name
  }
  $manifest = $package.Value.$packageVersion

  Write-Host
  if ($manifest.DisplayName) {
    Write-Host -ForegroundColor Green -NoNewline $manifest.DisplayName
    Write-Host -NoNewline " ($packageIdentifier)"
  }
  else {
    Write-Host -ForegroundColor Green -NoNewline $packageIdentifier
  }

  Write-Host -ForegroundColor DarkGray -NoNewline ' | version '
  Write-Host -ForegroundColor Cyan -NoNewline $packageVersion
  if ($manifest.ReleaseDate) {
    Write-Host -ForegroundColor DarkGray -NoNewline ' | '
    Write-Host -ForegroundColor DarkGray -NoNewline 'released on '
    Write-Host -ForegroundColor Cyan -NoNewline $manifest.ReleaseDate
  }
  Write-Host -ForegroundColor DarkGray -NoNewline ' | '
  Write-Host -ForegroundColor DarkGray -NoNewline 'by '
  Write-Host -ForegroundColor Cyan -NoNewline ($manifest.Developer -join ', ')
  Write-Host -ForegroundColor DarkGray -NoNewline ' | '
  Write-Host -ForegroundColor Cyan -NoNewline $manifest.Section
  Write-Host -ForegroundColor DarkGray -NoNewline ' | '
  if ($manifest.InstalledSize -lt 1024) {
    Write-Host -ForegroundColor Cyan -NoNewline "~ $($manifest.InstalledSize) KiB"
  }
  else {
    Write-Host -ForegroundColor Cyan -NoNewline "~ $([math]::Round($manifest.InstalledSize / 1024, 2)) MiB"
  }
  Write-Host

  Write-Host -ForegroundColor DarkGray '------'
  $manifest.Description

  if ($manifest.Website) {
    Write-Host -ForegroundColor DarkGray '------'
    Write-Host 'Webサイト:'
    $manifest.Website | ForEach-Object {
      Write-Host "  $_"
    }
  }

  Write-Host
  exit 0
}

function Split-PackageRelationShip {
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string]$Relationship
  )

  $parser = '^([0-9A-Za-z]+(?:[+\-.][0-9A-Za-z]+)*)(?: *\( *(<<|<=|=|>=|>>) *([0-9A-Za-z]+(?:[+\-.][0-9A-Za-z]+)*) *\))?$'

  if ($Relationship -match $parser) {
    $package = [pscustomobject]@{
      Identifier = $Matches[1]
      Operator   = $Matches[2]
      Version    = $Matches[3]
    }
    return $package
  }
  else {
    throw "Relationshipの形式が正しくありません: $Relationship"
  }
}

if ($Command -in $Commands.install.Key, $Commands.upgrade.Key) {
  $upgrade = $Command -eq $Commands.upgrade.Key
  if (-not $upgrade -and ($args.Count -lt 2)) {
    Write-Host -ForegroundColor Red 'パッケージ名が指定されていません'
    Write-Host -ForegroundColor Red '使用方法: .\butler.ps1 install <パッケージ名>[=<バージョン>] [<パッケージ名>[=<バージョン>]]...'
    exit 1
  }

  $packagesToInstall = @()
  $dependedPackages = @()

  if ($upgrade -and ($args.Count -lt 2)) {
    $specifiedPackages = $script:managedPackages | Where-Object { $_.Status -eq 'Installed' -and $_.IsVersionPinned -ne 'True' } | Select-Object -ExpandProperty Identifier
  }
  else {
    $specifiedPackages = $args[1..($args.Count - 1)] | Sort-Object -Unique
  }

  $specifiedPackages | ForEach-Object {
    $packageIdentifier = $_
    $packageVersion = $null
    if ($packageIdentifier.Contains('=')) {
      $packageIdentifier, $packageVersion = $packageIdentifier.Split('=')
    }

    if ($packagesToInstall | Where-Object { $_.Identifier -eq $packageIdentifier }) {
      Write-Host -ForegroundColor Red "パッケージが重複しています: $packageIdentifier"
      exit 1
    }

    if (-not $PackageManifests.ContainsKey($packageIdentifier)) {
      Write-Host -ForegroundColor Red "パッケージが見つかりません: $packageIdentifier"
      exit 1
    }
    $package = $PackageManifests.GetEnumerator() | Where-Object { $_.Key -eq $packageIdentifier } | Select-Object -First 1
    $packageIdentifier = $package.Key

    if ($packageVersion) {
      $packageVersion = $package.Value.psobject.Properties | Where-Object { $_.Name -eq $packageVersion } | Select-Object -First 1 -ExpandProperty Name
      if (-not $packageVersion) {
        Write-Host -ForegroundColor Red "バージョンが見つかりません: $packageIdentifier"
        exit 1
      }
      $packagesToInstall += [pscustomobject]@{
        Identifier          = $packageIdentifier
        InstallableVersions = @($packageVersion)
        IsVersionPinned     = $True
      }
    }
    else {
      $packagesToInstall += [pscustomobject]@{
        Identifier          = $packageIdentifier
        InstallableVersions = @($package.Value.psobject.Properties.Name)
        IsVersionPinned     = $False
      }
    }
  }

  Write-Host '依存関係を解決しています...' -NoNewline

  do {
    $isDependencyResolved = $true
    foreach ($package in @($dependedPackages) + @($packagesToInstall)) {
      $depends = $PackageManifests.($package.Identifier).($package.InstallableVersions[0]).Depends
      if ($depends) {
        $depends | ForEach-Object {
          $dependency = $_ | Split-PackageRelationShip
          $installedPackage = $script:managedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier -and ($_.Status -eq 'Installed') } | Select-Object -First 1
          if ($packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier }) {
            if ($dependency.Version) {
              switch ($dependency.Operator) {
                '<<' {
                  $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -lt $dependency.Version })
                  }
                }
                '<=' {
                  $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -le $dependency.Version })
                  }
                }
                '=' {
                  $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -eq $dependency.Version })
                  }
                }
                '>=' {
                  $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -ge $dependency.Version })
                  }
                }
                '>>' {
                  $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -gt $dependency.Version })
                  }
                }
              }
              if (-not $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier -and $_.InstallableVersions }) {
                Write-Host ' 失敗'
                Write-Host -ForegroundColor Red "$($package.Identifier) ($($package.Version)) は $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version)) に依存していますが、該当するバージョンが見つかりません"
                exit 1
              }
            }
          }
          elseif ($dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier }) {
            if ($dependency.Version) {
              switch ($dependency.Operator) {
                '<<' {
                  $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -lt $dependency.Version })
                  }
                }
                '<=' {
                  $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -le $dependency.Version })
                  }
                }
                '=' {
                  $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -eq $dependency.Version })
                  }
                }
                '>=' {
                  $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -ge $dependency.Version })
                  }
                }
                '>>' {
                  $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                    $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -gt $dependency.Version })
                  }
                }
              }
              if (-not ($dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier -and $_.InstallableVersions })) {
                Write-Host ' 失敗'
                Write-Host -ForegroundColor Red "$($package.Identifier) ($($package.Version)) の依存関係を解決できません: $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version))"
                Write-Host -ForegroundColor Red 'インストールしようとしている他のパッケージが異なるバージョンを要求している可能性があります'
                exit 1
              }
            }
          }
          elseif ($installedPackage) {
            if ($dependency.Version) {
              if ($installedPackage.IsVersionPinned -eq 'True') {
                switch ($dependency.Operator) {
                  '<<' {
                    if ($installedPackage.Version -lt $dependency.Version) {
                      $dependedPackages = @([pscustomobject]@{
                          Identifier          = $dependency.Identifier
                          InstallableVersions = @($PackageManifests.($dependency.Identifier).psobject.Properties.Name | Where-Object { $_ -lt $dependency.Version })
                        }) + $dependedPackages
                    }
                    else {
                      Write-Host ' 失敗'
                      Write-Host -ForegroundColor Red "依存パッケージ $($_.Identifier) は要求されたバージョンより新しいバージョンに固定されています: $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version))"
                      Write-Host -ForegroundColor Red "インストールされているバージョン: $($_.Identifier)=$($installedPackage.Version)"
                      exit 1
                    }
                  }
                  '<=' {
                    if ($installedPackage.Version -le $dependency.Version) {
                      $dependedPackages = @([pscustomobject]@{
                          Identifier          = $dependency.Identifier
                          InstallableVersions = @($PackageManifests.($dependency.Identifier).psobject.Properties.Name | Where-Object { $_ -le $dependency.Version })
                        }) + $dependedPackages
                    }
                    else {
                      Write-Host ' 失敗'
                      Write-Host -ForegroundColor Red "依存パッケージ $($_.Identifier) は要求されたバージョンより新しいバージョンに固定されています: $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version))"
                      Write-Host -ForegroundColor Red "インストールされているバージョン: $($_.Identifier)=$($installedPackage.Version)"
                      exit 1
                    }
                  }
                  '=' {
                    if ($installedPackage.Version -ne $dependency.Version) {
                      Write-Host ' 失敗'
                      Write-Host -ForegroundColor Red "依存パッケージ $($_.Identifier) は要求されたバージョンとは異なるバージョンに固定されています: $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version))"
                      Write-Host -ForegroundColor Red "インストールされているバージョン: $($_.Identifier)=$($installedPackage.Version)"
                      exit 1
                    }
                  }
                  '>=' {
                    if ($installedPackage.Version -ge $dependency.Version) {
                      $dependedPackages = @([pscustomobject]@{
                          Identifier          = $dependency.Identifier
                          InstallableVersions = @($PackageManifests.($dependency.Identifier).psobject.Properties.Name | Where-Object { $_ -ge $dependency.Version })
                        }) + $dependedPackages
                    }
                    else {
                      Write-Host ' 失敗'
                      Write-Host -ForegroundColor Red "依存パッケージ $($_.Identifier) は要求されたバージョンより古いバージョンに固定されています: $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version))"
                      Write-Host -ForegroundColor Red "インストールされているバージョン: $($_.Identifier)=$($installedPackage.Version)"
                      exit 1
                    }
                  }
                  '>>' {
                    if ($installedPackage.Version -gt $dependency.Version) {
                      $dependedPackages = @([pscustomobject]@{
                          Identifier          = $dependency.Identifier
                          InstallableVersions = @($PackageManifests.($dependency.Identifier).psobject.Properties.Name | Where-Object { $_ -gt $dependency.Version })
                        }) + $dependedPackages
                    }
                    else {
                      Write-Host ' 失敗'
                      Write-Host -ForegroundColor Red "依存パッケージ $($_.Identifier) は要求されたバージョンより古いバージョンに固定されています: $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version))"
                      Write-Host -ForegroundColor Red "インストールされているバージョン: $($_.Identifier)=$($installedPackage.Version)"
                      exit 1
                    }
                  }
                }
              }
              else {
                switch ($dependency.Operator) {
                  '<<' {
                    if ($installedPackage.Version -lt $dependency.Version) {
                      $dependedPackages = @([pscustomobject]@{
                          Identifier          = $dependency.Identifier
                          InstallableVersions = @($PackageManifests.($dependency.Identifier).psobject.Properties.Name | Where-Object { $_ -lt $dependency.Version })
                        }) + $dependedPackages
                    }
                  }
                  '<=' {
                    if ($installedPackage.Version -le $dependency.Version) {
                      $dependedPackages = @([pscustomobject]@{
                          Identifier          = $dependency.Identifier
                          InstallableVersions = @($PackageManifests.($dependency.Identifier).psobject.Properties.Name | Where-Object { $_ -le $dependency.Version })
                        }) + $dependedPackages
                    }
                  }
                  '=' {
                    if ($installedPackage.Version -ne $dependency.Version) {
                      $dependedPackages = @([pscustomobject]@{
                          Identifier          = $dependency.Identifier
                          InstallableVersions = @($dependency.Version)
                        }) + $dependedPackages
                    }
                  }
                  '>=' {
                    if ($installedPackage.Version -ge $dependency.Version) {
                      $dependedPackages = @([pscustomobject]@{
                          Identifier          = $dependency.Identifier
                          InstallableVersions = @($PackageManifests.($dependency.Identifier).psobject.Properties.Name | Where-Object { $_ -ge $dependency.Version })
                        }) + $dependedPackages
                    }
                  }
                  '>>' {
                    if ($installedPackage.Version -gt $dependency.Version) {
                      $dependedPackages = @([pscustomobject]@{
                          Identifier          = $dependency.Identifier
                          InstallableVersions = @($PackageManifests.($dependency.Identifier).psobject.Properties.Name | Where-Object { $_ -gt $dependency.Version })
                        }) + $dependedPackages
                    }
                  }
                }
                if (-not $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier -and $_.InstallableVersions }) {
                  Write-Host ' 失敗'
                  Write-Host -ForegroundColor Red "$($package.Identifier) ($($package.Version)) の依存関係を解決できません: $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version))"
                  Write-Host -ForegroundColor Red 'インストールしようとしている他のパッケージが異なるバージョンを要求している可能性があります'
                  exit 1
                }
              }
            }
          }
          else {
            $isDependencyResolved = $false
            $dependedPackage = $PackageManifests.GetEnumerator() | Where-Object { $_.Key -eq $dependency.Identifier } | Select-Object -First 1
            if (-not $dependedPackage) {
              Write-Host ' 失敗'
              Write-Host -ForegroundColor Red "依存しているパッケージが見つかりません: $($_.Identifier)"
              exit 1
            }
            if ($dependency.Version) {
              switch ($dependency.Operator) {
                '<<' {
                  $dependedPackages = @([pscustomobject]@{
                      Identifier          = $dependency.Identifier
                      InstallableVersions = @($dependedPackage.Value.psobject.Properties.Name | Where-Object { $_ -lt $dependency.Version })
                    }) + $dependedPackages
                }
                '<=' {
                  $dependedPackages = @([pscustomobject]@{
                      Identifier          = $dependency.Identifier
                      InstallableVersions = @($dependedPackage.Value.psobject.Properties.Name | Where-Object { $_ -le $dependency.Version })
                    }) + $dependedPackages
                }
                '=' {
                  $dependedPackages = @([pscustomobject]@{
                      Identifier          = $dependency.Identifier
                      InstallableVersions = @($dependency.Version)
                    }) + $dependedPackages
                }
                '>=' {
                  $dependedPackages = @([pscustomobject]@{
                      Identifier          = $dependency.Identifier
                      InstallableVersions = @($dependedPackage.Value.psobject.Properties.Name | Where-Object { $_ -ge $dependency.Version })
                    }) + $dependedPackages
                }
                '>>' {
                  $dependedPackages = @([pscustomobject]@{
                      Identifier          = $dependency.Identifier
                      InstallableVersions = @($dependedPackage.Value.psobject.Properties.Name | Where-Object { $_ -gt $dependency.Version })
                    }) + $dependedPackages
                }
              }
              if (-not ($dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier -and $_.InstallableVersions })) {
                Write-Host ' 失敗'
                Write-Host -ForegroundColor Red "$($dependedPackage.Identifier) ($($dependedPackage.Version)) の依存関係を解決できません: $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version))"
                Write-Host -ForegroundColor Red 'インストールしようとしている他のパッケージが異なるバージョンを要求している可能性があります'
                exit 1
              }
            }
            else {
              $dependedPackages += [pscustomobject]@{
                Identifier          = $dependency.Identifier
                InstallableVersions = @($dependedPackage.Value.psobject.Properties.Name)
              }
            }
          }
        }
      }
    }
  } until ($isDependencyResolved)

  $script:managedPackages | Where-Object { $_.Status -eq 'Installed' } | ForEach-Object {
    $packageIdentifier = $_.Identifier
    $packageVersion = $_.Version
    $depends = $PackageManifests.$packageIdentifier.$packageVersion.Depends
    if ($depends) {
      $depends | ForEach-Object {
        $dependency = $_ | Split-PackageRelationShip
        if ($dependency.Version) {
          switch ($dependency.Operator) {
            '<<' {
              $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -lt $dependency.Version })
              }
              $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -lt $dependency.Version })
              }
            }
            '<=' {
              $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -le $dependency.Version })
              }
              $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -le $dependency.Version })
              }
            }
            '=' {
              $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -eq $dependency.Version })
              }
              $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -eq $dependency.Version })
              }
            }
            '>=' {
              $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -ge $dependency.Version })
              }
              $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -ge $dependency.Version })
              }
            }
            '>>' {
              $dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -gt $dependency.Version })
              }
              $packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier } | ForEach-Object {
                $_.InstallableVersions = @($_.InstallableVersions | Where-Object { $_ -gt $dependency.Version })
              }
            }
          }
          if (
            (@($dependedPackages) + @($packagesToInstall) | Where-Object { $_.Identifier -eq $dependency.Identifier }) -and
            -not (
              ($dependedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier -and $_.InstallableVersions }) -or
              ($packagesToInstall | Where-Object { $_.Identifier -eq $dependency.Identifier -and $_.InstallableVersions })
            )
          ) {
            Write-Host ' 失敗'
            Write-Host -ForegroundColor Red "$packageIdentifier ($packageVersion) は $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version)) に依存しています"
            exit 1
          }
        }
      }
    }
  }

  Write-Host ' 完了'

  foreach ($dependency in $dependedPackages) {
    $installedPackage = $script:managedPackages | Where-Object { $_.Identifier -eq $dependency.Identifier -and ($_.Status -eq 'Installed') } | Select-Object -First 1
    if ($installedPackage.Version -eq $dependency.InstallableVersions[0]) {
      Write-Debug -Message "依存パッケージは既に最新バージョンです: $($dependency.Identifier) ($($dependency.InstallableVersions[0]))"
      $dependedPackages = @($dependedPackages | Where-Object { $_.Identifier -ne $dependency.Identifier })
    }
  }

  foreach ($packageToInstall in $packagesToInstall) {
    $installedPackage = $script:managedPackages | Where-Object { $_.Identifier -eq $packageToInstall.Identifier -and ($_.Status -eq 'Installed') } | Select-Object -First 1
    if ($installedPackage) {
      if ($installedPackage.Version -eq $packageToInstall.InstallableVersions[0]) {
        Write-Host "パッケージは既に最新バージョンです: $($packageToInstall.Identifier) ($($packageToInstall.InstallableVersions[0]))"
        $packagesToInstall = @($packagesToInstall | Where-Object { $_.Identifier -ne $packageToInstall.Identifier })
      }
    }
  }

  if ($packagesToInstall.Count -eq 0) {
    Write-Host '操作の対象となるパッケージはありません'
    exit 0
  }

  if ($dependedPackages.Count -gt 0) {
    Write-Host '以下の追加パッケージがインストールされます:'
    $consoleWidthRemain = $ConsoleWidth - 2
    Write-Host -NoNewline '  '
    $dependedPackages | Sort-Object -Property Identifier | ForEach-Object {
      $consoleWidthRemain -= $_.Identifier.Length
      if ($consoleWidthRemain -lt 0) {
        Write-Host
        Write-Host -NoNewline '  '
        $consoleWidthRemain = $ConsoleWidth - $_.Identifier.Length - 2
      }
      Write-Host -NoNewline "$($_.Identifier) "
      $consoleWidthRemain -= 1
    }
    Write-Host
  }

  $installedSize = 0

  if ($upgrade) {
    Write-Host '以下のパッケージがアップグレードされます:'
  }
  else {
    Write-Host '以下のパッケージが新たにインストールされます:'
  }
  $consoleWidthRemain = $ConsoleWidth - 2
  Write-Host -NoNewline '  '
  @($dependedPackages) + @($packagesToInstall) | Sort-Object -Property Identifier | ForEach-Object {
    $installedSize += $PackageManifests.$($_.Identifier).$($_.InstallableVersions[0]).InstalledSize
    $consoleWidthRemain -= $_.Identifier.Length
    if ($consoleWidthRemain -lt 0) {
      Write-Host
      Write-Host -NoNewline '  '
      $consoleWidthRemain = $ConsoleWidth - $_.Identifier.Length - 2
    }
    Write-Host -NoNewline "$($_.Identifier) "
    $consoleWidthRemain -= 1
  }
  Write-Host

  if ($installedSize -lt 1024) {
    Write-Host "この操作後に追加で $installedSize KiB のディスク容量が消費されます"
  }
  else {
    Write-Host "この操作後に追加で $([math]::Round($installedSize / 1024, 2)) MiB のディスク容量が消費されます"
  }

  do {
    Write-Host -NoNewline '続行しますか? [Y/n] '
    $answer = Read-Host
  } until ([string]::IsNullOrEmpty($answer) -or ($answer -in @('Y', 'n')))
  if ($answer -eq 'n') {
    Write-Host '中断しました'
    exit 0
  }

  $dependedPackages | ForEach-Object {
    $packageIdentifier = $_.Identifier
    $packageVersion = $_.InstallableVersions[0]
    $manifest = $PackageManifests.$packageIdentifier.$packageVersion

    $packageDirectory = Join-Path -Path $PackagesDirectory -ChildPath $packageIdentifier
    if (-not (Test-Path -Path $packageDirectory -PathType Container)) {
      $null = New-Item -Path $packageDirectory -ItemType Directory
    }

    $installedPackage = $script:managedPackages | Where-Object { $_.Identifier -eq $packageIdentifier -and ($_.Status -eq 'Installed') } | Select-Object -First 1
    if ($installedPackage) {
      $installedPackageVersion = $installedPackage.Version
      $installedPackageManifest = $PackageManifests.$packageIdentifier.$installedPackageVersion
      & (Join-Path -Path $PSScriptRoot -ChildPath './commands/RemovePackage.ps1') -Identifier $packageIdentifier -Version $installedPackageVersion -Manifest $installedPackageManifest -RootDirectory $RootDirectory -PackageDirectory $packageDirectory -ManagedFilesPath $ManagedFilesPath
      $managedFiles = @(Import-Csv -LiteralPath $ManagedFilesPath)
      if (
        $purge -or (
          -not ($managedFiles | Where-Object { $_.Identifier -eq $packageIdentifier }) -and
          -not ($installedPackageManifest.ConfFiles -and ($installedPackageManifest.ConfFiles | ForEach-Object { Test-Path (Join-Path -Path $RootDirectory -ChildPath $_) } | Where-Object { $_ -eq $true }))
        )
      ) {
        $script:managedPackages = @($script:managedPackages | Where-Object { -not ($_.Identifier -eq $packageIdentifier -and ($_.Status -eq 'Installed')) })
      }
      else {
        $script:managedPackages | Where-Object { $_.Identifier -eq $packageIdentifier -and ($_.Status -eq 'Installed') } | ForEach-Object {
          $_.Status = 'Removed'
        }
      }
    }

    & (Join-Path -Path $PSScriptRoot -ChildPath './commands/InstallPackage.ps1') -Identifier $packageIdentifier -Version $packageVersion -Manifest $manifest -RootDirectory $RootDirectory -CacheDirectory $PackagesCacheDirectory -PackageDirectory $packageDirectory -ManagedFilesPath $ManagedFilesPath

    $script:managedPackages += [pscustomobject]@{
      Identifier       = $packageIdentifier
      Developer        = @($manifest.Developer) | Select-Object -First 1
      Version          = $packageVersion
      Status           = 'Installed'
      InstallationType = 'Auto'
      IsVersionPinned  = $false
    }
  }

  $packagesToInstall | ForEach-Object {
    $packageIdentifier = $_.Identifier
    $packageVersion = $_.InstallableVersions[0]
    $manifest = $PackageManifests.$packageIdentifier.$packageVersion

    $packageDirectory = Join-Path -Path $PackagesDirectory -ChildPath $packageIdentifier
    if (-not (Test-Path -Path $packageDirectory -PathType Container)) {
      $null = New-Item -Path $packageDirectory -ItemType Directory
    }

    $installedPackage = $script:managedPackages | Where-Object { $_.Identifier -eq $packageIdentifier -and ($_.Status -eq 'Installed') } | Select-Object -First 1
    if ($installedPackage) {
      $installedPackageVersion = $installedPackage.Version
      $installedPackageManifest = $PackageManifests.$packageIdentifier.$installedPackageVersion
      & (Join-Path -Path $PSScriptRoot -ChildPath './commands/RemovePackage.ps1') -Identifier $packageIdentifier -Version $installedPackageVersion -Manifest $installedPackageManifest -RootDirectory $RootDirectory -PackageDirectory $packageDirectory -ManagedFilesPath $ManagedFilesPath
      $managedFiles = @(Import-Csv -LiteralPath $ManagedFilesPath)
      if (
        $purge -or (
          -not ($managedFiles | Where-Object { $_.Identifier -eq $packageIdentifier }) -and
          -not ($installedPackageManifest.ConfFiles -and ($installedPackageManifest.ConfFiles | ForEach-Object { Test-Path (Join-Path -Path $RootDirectory -ChildPath $_) } | Where-Object { $_ -eq $true }))
        )
      ) {
        $script:managedPackages = @($script:managedPackages | Where-Object { -not ($_.Identifier -eq $packageIdentifier -and ($_.Status -eq 'Installed')) })
      }
      else {
        $script:managedPackages | Where-Object { $_.Identifier -eq $packageIdentifier -and ($_.Status -eq 'Installed') } | ForEach-Object {
          $_.Status = 'Removed'
        }
      }
    }

    & (Join-Path -Path $PSScriptRoot -ChildPath './commands/InstallPackage.ps1') -Identifier $packageIdentifier -Version $packageVersion -Manifest $manifest -RootDirectory $RootDirectory -CacheDirectory $PackagesCacheDirectory -PackageDirectory $packageDirectory -ManagedFilesPath $ManagedFilesPath

    $script:managedPackages += [pscustomobject]@{
      Identifier       = $packageIdentifier
      Developer        = @($manifest.Developer) | Select-Object -First 1
      Version          = $packageVersion
      Status           = 'Installed'
      InstallationType = 'Manual'
      IsVersionPinned  = $_.IsVersionPinned
    }
  }

  try {
    (($script:managedPackages | ConvertTo-Csv -NoTypeInformation -UseQuotes Never) -join "`n") + "`n" | Set-Content -LiteralPath $managedPackagesPath -Force -NoNewline
  }
  catch {
    Write-Error -Message "ファイルの書き込みに失敗しました: $managedPackagesPath"
    throw
  }
}

if ($Command -eq $Commands.reinstall.Key) {
  if ($args.Count -lt 2) {
    Write-Host '全てのパッケージが再インストールされます'
    Write-Host -NoNewline '続行しますか? [y/N] '
    do {
      $answer = Read-Host
    } until ([string]::IsNullOrEmpty($answer) -or ($answer -in @('y', 'N')))
    if ($answer -ne 'Y') {
      Write-Host '中断しました'
      exit 0
    }
    $packagesToReinstall = $script:managedPackages | Where-Object { $_.Status -eq 'Installed' } | ForEach-Object { $_.Identifier }
  }
  else {
    $packagesToReinstall = $args[1..($args.Count - 1)] | Sort-Object -Unique
  }

  $packagesToReinstall | ForEach-Object {
    $packageIdentifier = $_
    $managedPackage = $script:managedPackages | Where-Object { $_.Identifier -eq $packageIdentifier -and ($_.Status -eq 'Installed') } | Select-Object -First 1
    if ($managedPackage) {
      $packageIdentifier = $managedPackage.Identifier
      $packagesToReinstall = @($packagesToReinstall | Where-Object { $_ -ne $packageIdentifier })
      $packagesToReinstall += $packageIdentifier
    }
    else {
      Write-Host -ForegroundColor Red "パッケージがインストールされていません: $packageIdentifier"
      exit 1
    }
  }

  $packagesToReinstall | ForEach-Object {
    $packageIdentifier = $_
    $installedPackage = $script:managedPackages | Where-Object { $_.Identifier -eq $packageIdentifier -and ($_.Status -eq 'Installed') } | Select-Object -First 1
    $packageVersion = $installedPackage.Version
    $manifest = $PackageManifests.$packageIdentifier.$packageVersion

    $packageDirectory = Join-Path -Path $PackagesDirectory -ChildPath $packageIdentifier
    if (-not (Test-Path -Path $packageDirectory -PathType Container)) {
      $null = New-Item -Path $packageDirectory -ItemType Directory
    }

    & (Join-Path -Path $PSScriptRoot -ChildPath './commands/RemovePackage.ps1') -Identifier $packageIdentifier -Version $packageVersion -Manifest $manifest -RootDirectory $RootDirectory -PackageDirectory $packageDirectory -ManagedFilesPath $ManagedFilesPath
    & (Join-Path -Path $PSScriptRoot -ChildPath './commands/InstallPackage.ps1') -Identifier $packageIdentifier -Version $packageVersion -Manifest $manifest -RootDirectory $RootDirectory -CacheDirectory $PackagesCacheDirectory -PackageDirectory $packageDirectory -ManagedFilesPath $ManagedFilesPath
  }
}

if ($Command -in $Commands.remove.Key, $Commands.purge.Key, $Commands.autoremove.Key, $Commands.autopurge.Key) {
  $Command = $Command.ToLower()
  $auto = $Command -in $Commands.autoremove.Key, $Commands.autopurge.Key
  $purge = $Command -in $Commands.purge.Key, $Commands.autopurge.Key

  if (-not $auto -and ($args.Count -lt 2)) {
    Write-Host -ForegroundColor Red 'パッケージ名が指定されていません'
    Write-Host -ForegroundColor Red "使用方法: .\butler.ps1 $Command <パッケージ名> [<パッケージ名>]..."
    exit 1
  }

  if ($auto) {
    if ($purge) {
      $packagesToRemove = $script:managedPackages | Where-Object { $_.InstallationType -eq 'Auto' } | ForEach-Object { $_.Identifier }
    }
    else {
      $packagesToRemove = $script:managedPackages | Where-Object { $_.InstallationType -eq 'Auto' -and ($_.Status -eq 'Installed') } | ForEach-Object { $_.Identifier }
    }
  }
  else {
    $packagesToRemove = $args[1..($args.Count - 1)] | Sort-Object -Unique
  }

  $packagesToRemove | ForEach-Object {
    $packageIdentifier = $_
    $managedPackage = $script:managedPackages | Where-Object { $_.Identifier -eq $packageIdentifier } | Select-Object -First 1
    if ($managedPackage) {
      $packageIdentifier = $managedPackage.Identifier
      $packagesToRemove = @($packagesToRemove | Where-Object { $_ -ne $packageIdentifier })
      $packagesToRemove += $packageIdentifier
    }
    else {
      Write-Host -ForegroundColor Red "パッケージは管理されていません: $packageIdentifier"
      exit 1
    }
  }

  do {
    $isDependencyResolved = $true
    $script:managedPackages | Where-Object { $_.Status -eq 'Installed' } | ForEach-Object {
      $packageIdentifier = $_.Identifier
      $packageVersion = $_.Version
      $depends = $PackageManifests.$packageIdentifier.$packageVersion.Depends
      if ($depends) {
        $depends | ForEach-Object {
          $dependency = $_ | Split-PackageRelationShip
          foreach ($packageToRemove in $packagesToRemove) {
            if ($dependency.Identifier -eq $packageToRemove -and $packageIdentifier -notin $packagesToRemove) {
              $isDependencyResolved = $false
              if (-not $auto) {
                Write-Host -ForegroundColor Red "$packageIdentifier ($packageVersion) は $($dependency.Identifier) ($($dependency.Operator) $($dependency.Version)) に依存しています"
              }
              $packagesToRemove = @($packagesToRemove | Where-Object { $_ -ne $packageToRemove })
            }
          }
        }
      }
    }
  } until ($isDependencyResolved)

  if ($packagesToRemove.Count -eq 0) {
    Write-Host '操作の対象となるパッケージはありません'
    exit 0
  }

  if ($purge) {
    Write-Host '以下のパッケージが完全に削除されます:'
  }
  else {
    Write-Host '以下のパッケージが削除されます:'
  }
  $consoleWidthRemain = $ConsoleWidth - 2
  Write-Host -NoNewline '  '
  $packagesToRemove | Sort-Object | ForEach-Object {
    $ConsoleWidthRemain -= $_.Length
    if ($consoleWidthRemain -lt 0) {
      Write-Host
      Write-Host -NoNewline '  '
      $consoleWidthRemain = $ConsoleWidth - $_.Length - 2
    }
    Write-Host -NoNewline "$_ "
    $consoleWidthRemain -= 1
  }
  Write-Host

  do {
    Write-Host -NoNewline '続行しますか? [Y/n] '
    $answer = Read-Host
  } until ([string]::IsNullOrEmpty($answer) -or ($answer -in @('Y', 'n')))
  if ($answer -eq 'n') {
    Write-Host '中断しました'
    exit 0
  }

  $packagesToRemove | ForEach-Object {
    $packageIdentifier = $_
    $managedPackage = $script:managedPackages | Where-Object { $_.Identifier -eq $packageIdentifier } | Select-Object -First 1
    $packageVersion = $managedPackage.Version
    $manifest = $PackageManifests.$packageIdentifier.$packageVersion

    $packageDirectory = Join-Path -Path $PackagesDirectory -ChildPath $packageIdentifier
    & (Join-Path -Path $PSScriptRoot -ChildPath './commands/RemovePackage.ps1') -Identifier $packageIdentifier -Version $packageVersion -Manifest $manifest -RootDirectory $RootDirectory -PackageDirectory $packageDirectory -ManagedFilesPath $ManagedFilesPath -Purge:$purge

    $managedFiles = @(Import-Csv -LiteralPath $ManagedFilesPath)

    if (
      $purge -or (
        -not ($managedFiles | Where-Object { $_.Identifier -eq $packageIdentifier }) -and
        -not ($manifest.ConfFiles -and ($manifest.ConfFiles | ForEach-Object { Test-Path (Join-Path -Path $RootDirectory -ChildPath $_) } | Where-Object { $_ -eq $true }))
      )
    ) {
      $script:managedPackages = @($script:managedPackages | Where-Object { $_.Identifier -ne $packageIdentifier })
    }
    else {
      $script:managedPackages | Where-Object { $_.Identifier -eq $packageIdentifier } | ForEach-Object {
        $_.Status = 'Removed'
      }
    }
  }

  try {
    (($script:managedPackages | ConvertTo-Csv -NoTypeInformation -UseQuotes Never) -join "`n") + "`n" | Set-Content -LiteralPath $managedPackagesPath -Force -NoNewline
  }
  catch {
    Write-Error -Message "ファイルの書き込みに失敗しました: $managedPackagesPath"
    throw
  }
}
