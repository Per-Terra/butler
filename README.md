# BUtler - AviUtl用コマンドラインパッケージマネージャー

[日本語(Japanese)](/README.md) • [English](/docs/README-en.md)

BUtlerはAviUtl用のコマンドラインパッケージマネージャーです。

## 特徴

### 豊富なパッケージ

- 100を超えるパッケージがBUtlerの[コミュニティリポジトリ](https://github.com/Per-Terra/butler-pkgs)に登録済み。あらゆるプラグインを簡単にインストールできます。

### シンプル設計

- すべてのファイルはBUtlerの管理フォルダー内に展開され、必要なファイルのみが**シンボリックリンクとして**インストールされます。
  - ごちゃごちゃになりがちなAviUtlのフォルダを最小限に保ちつつ、開発者から提供されたドキュメントも見逃すことはありません。
- 設定ファイルなどは**コピー**されます。
  - 変更して良いファイルとそうでないファイルが一目瞭然。誤操作を防ぎます。

### apt風の簡単操作

- Debian系のLinuxディストリビューションで採用されているパッケージマネージャー、aptに似た雰囲気を持つコマンド体系を採用。迷うことなく使い始めることができます。

### 依存関係も自動で解決

- 必要なパッケージは自動でインストールされるので、手間がかかりません。

## インストール

### PowerShell 7.4以上をインストールする

- PowerShellのインストール方法は[Microsoftの記事](https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows)を確認してください。
- もしくは、次のコマンドで最新のバージョンをインストールできます。

  ```cmd
  winget install --id Microsoft.Powershell --source winget
  ```

### BUtlerをインストールする

- BUtlerをインストールするフォルダーを作成し、そのフォルダーに移動します。
- 以下のコマンドをコピーし、アドレスバーに貼り付けてEnterキーを押します。

  ```cmd
  pwsh -ExecutionPolicy Bypass -Command "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Per-Terra/butler/main/installer.ps1'))"
  ```

- `BUtler` という名称のショートカットをダブルクリックして、プロンプトが起動すればインストールは成功です。

- 初回起動時は最初に `update` コマンドを実行する必要があります。

## 利用可能なコマンド

### `help`

- 利用可能なコマンドを表示します。

### `list`

- インストールされたパッケージを一覧表示します。

### `search <検索クエリ>`

- 利用可能なパッケージを検索して、一覧表示します。

### `show <パッケージ名>`

- 指定されたパッケージの詳細な情報を表示します。

### `install <パッケージ名>[=<バージョン>] [<パッケージ名>[=<バージョン>]]...`

- 指定されたパッケージをインストールします。
- バージョンを指定するとそのバージョンで固定され、アップグレードされることはありません。
- 例: [aviutl/](https://scrapbox.io/aviutl/セットアップ) の推奨構成をインストールする
  ```
  install aviutl exedit=0.92 L-SMASH-Works InputPipePlugin easymp4 patch.aul
  ```

### `reinstall [<パッケージ名>]...`

- 指定されたパッケージを再インストールします。
- 何も指定しなければ全てのパッケージを再インストールします。

### `remove <パッケージ名> [<パッケージ名>]...`

- 指定されたパッケージを削除します。
- 設定ファイルは残ります。

### `purge <パッケージ名> [<パッケージ名>]...`

- 指定されたパッケージを設定ファイルを含めて完全に削除します。
- remove後でも実行できます。

### `autoremove`, `autopurge`

- 自動でインストールされたが、もはや必要でないパッケージを削除、または完全に削除します。

### `update`

- パッケージマニフェストを更新します。

### `upgrade [<パッケージ名>...]`

- パッケージ名を指定した場合の動作は `install` と同じです。
- パッケージ名を指定しなかった場合はインストールされた全てのパッケージをアップグレードします。

### `interactive`

- 対話型シェルを起動します。(コマンドを何も指定せず起動したときの既定値)

## 付録

### キャッシュについて

- `.butler/cache/` はキャッシュフォルダーです。このフォルダーはいつ削除しても動作に問題はありません。容量を圧迫している際にお試しください。
- Windowsではジャンクションを作成することで別のフォルダーにキャッシュを保存することができます。
  - 複数のフォルダにBUtlerをインストールしていて、キャッシュを共通化したい場合に有効です。並列実行は考慮されていませんのでお気をつけください。

### 軽量にして持ち運ぶ

- `.butler/packages` フォルダー以下にはファイルの実体が含まれています。このフォルダーを削除してしまっても `reinstall` コマンドで復旧することができます。
- この仕様を利用して、 `.butler/cache` フォルダーと `.butler/packages` フォルダーを削除し、ZIP圧縮することで設定ファイルのみを持ったアーカイブを作成することができます。
  - この際、シンボリックリンクはZIPファイルの仕様上保持されません。
- アーカイブを展開したら、BUtlerを起動し `update` コマンドと `reinstall` コマンドを順に実行することで元の環境を復元することができます。

## ライセンス

[MIT License](LICENSE)に基づく
