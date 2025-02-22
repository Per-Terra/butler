# BUtler - AviUtl用コマンドラインパッケージマネージャー

BUtler（バトラーと発音します）はAviUtl用のコマンドラインパッケージマネージャーです。

## 特徴

- **apt風の簡単操作**：Debian系のLinuxディストリビューションで採用されているパッケージマネージャー、aptに似た雰囲気を持つコマンド体系を採用。迷うことなく使い始めることができます。

- **豊富なパッケージ**：200を超えるパッケージがBUtlerの[コミュニティリポジトリ](https://github.com/Per-Terra/butler-pkgs)に登録済み。あらゆるプラグインやスクリプトを簡単にインストールできます。

- **依存関係も自動で解決**：必要なパッケージは自動でインストール。バージョンの相違などによる不具合に悩むこともありません。

- **シンプル・イズ・ベスト**：全てのファイルをBUtlerの管理フォルダー内に展開。動作に必要なファイルはシンボリックリンク、設定ファイルはコピーがあるべき場所に配置されます。

## インストール

### PowerShell 7.4以上をインストールする

- PowerShellのインストール方法については[Microsoftの記事](https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows)をご参照ください。
- もしくは、以下のコマンドで最新のPowerShellをインストールできます。

  ```cmd
  winget install --id Microsoft.Powershell --source winget
  ```

### 開発者モードを有効にする

- BUtlerでシンボリックリンクを使用したパッケージの管理を行うためには、開発者モードを有効にして標準ユーザー権限でシンボリックリンクを作成可能にする必要があります。

> [!TIP]
> 開発者モードを有効にできない、もしくはNTFS以外のファイルシステムを利用していてシンボリックリンクを利用できない場合は常にコピーを使用するように[設定](#設定)を変更できます。

- Win + Rを押して「ファイル名を指定して実行」を開き、以下のURIを貼り付けて開きます。

  ```text
  ms-settings:developers
  ```

- 「開発者モード」をオンにします。プロンプトが表示されたら「はい」を選択します。

### BUtlerをインストールする

- AviUtlをセットアップするフォルダーを作成し、そのフォルダーに移動します。
  - セットアップ済みの環境への追加はサポートされていません。
- 以下のコマンドをコピーし、アドレスバーに貼り付けてEnterキーを押します。

  ```pwsh
  pwsh -ExecutionPolicy Bypass -Command "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Per-Terra/butler/main/installer.ps1'))"
  ```

- `BUtler` という名称のショートカットをダブルクリックして、プロンプトが起動すればインストールは成功です。

## 使い方

### AviUtlと拡張編集をインストールする

- 最新のパッケージマニフェストを取得したら、まずはAviUtlと拡張編集をインストールしてみましょう。
- BUtlerを起動して、以下のコマンドを実行します。

```shell
install aviutl exedit=0.92
```

- `install` はパッケージをインストールするコマンドです。
- パッケージはそれぞれ固有の識別子を持ちます。大文字と小文字は区別されません。
- バージョンを指定するときは、識別子とバージョンを `=` で結びます。
  - バージョンを指定するとそのバージョンに固定されます。バージョンが固定されたパッケージが自動的にアップグレード（ダウングレード）されることはありません。
  - バージョンの固定を解除するときは、バージョンを指定せずに再度 `install` コマンドを実行します。

### パッケージを削除する

- `remove` コマンドと `purge` コマンドは、どちらもパッケージを削除するコマンドですが、動作が少しだけ異なります。
- 例として、先程インストールしたAviUtlと拡張編集を削除してみましょう。
- 必ずAviUtlを終了してから実行してください。
  - もしまだ一度も起動していないのなら、違いが分かりやすいようにいったん起動して、終了しましょう。

```shell
remove aviutl exedit
```

- `remove` コマンドは、設定ファイルを保ったままパッケージを削除します。
  - フォルダー内には `aviutl.ini`、`aviutl.sav`、`デフォルト.cfg`が依然として残っているはずです。
- 「`exedit.ini` は？」と思いましたか？ 流石です。
  - `remove` コマンドでもユーザーによって変更されていないファイルは自動的に削除されます。
  - もしあなたが `exedit.ini` に変更を加えていたのなら削除されずに残っているはずです。
- では、さらに `purge` コマンドも実行してみましょう。

```shell
purge aviutl
```

- これで、先程の3つのファイルも削除されました。
- `purge` コマンドは、設定ファイルも含めてパッケージのすべてのファイルを削除します。
  - 設定ファイルには（パッケージマニフェストに登録されていれば）パッケージによって自動生成されるファイルも含みます。
- `remove` コマンド実行後も、設定ファイルが残っているパッケージはBUtlerの管理下に保たれます。
  - 任意のタイミングで `purge` コマンドを実行して、残っているファイルを削除することができます。

### パッケージを検索する

- `search` コマンドを使用して、インストール可能なパッケージを検索することができます。
- 例として、「エンコード」を指定して検索してみましょう。

```shell
search エンコード
```

<details>
<summary>実行結果</summary>

```text
Identifier  Version    ReleaseDate Developer Section       DisplayName               Description
----------  -------    ----------- --------- -------       -----------               -----------
cmpwnd      0.1        2016-02-07  aoytsk    Plugin/Other  比較ウィンドウ            2つの動画を比較するためのプラグイン…
easymp4     0.1.1-fix  2020-04-23  aoytsk    Plugin/Output かんたんMP4出力           MP4でエンコードする出力プラグイン
ffmpegOut   1.09       2023-10-25  rigaya    Plugin/Output                           ffmpegを使用してエンコードを行う出力プラグイン
NVEnc       7.40       2023-12-10  rigaya    Plugin/Output                           NVIDIAのNVEncを使用してエンコードを行う出力プラグイン…
QSVEnc      7.58       2024-01-04  rigaya    Plugin/Output                           Intel Media SDK を使用してエンコードを行う出力プラグイン…
svtAV1guiEx 1.23       2023-10-22  rigaya    Plugin/Output 拡張 SVT-AV1 出力(GUI) Ex SVT-AV1を使用してエンコードを行う出力プラグイン
VCEEnc      8.21       2023-12-10  rigaya    Plugin/Output                           AMDのVCE(VideoCodecEngine)を使用してエンコードを行う出力プラグイン…
VVenCguiEx  0.00-beta4 2023-05-09  rigaya    Plugin/Output 拡張 VVenC 出力(GUI) Ex   VVenCを使用してエンコードを行う出力プラグイン
x264guiEx   3.27       2023-12-06  rigaya    Plugin/Output 拡張 x264 出力(GUI) Ex    x264を使用してエンコードを行う出力プラグイン…
x265guiEx   4.16       2023-10-12  rigaya    Plugin/Output 拡張 x265 出力(GUI) Ex    x265を使用してエンコードを行う出力プラグイン…
```

</details>

- Identifier（識別子）、DisplayName（表示名）またはDescription（説明）のいずれかに「エンコード」を含むパッケージが表示されました。
- パッケージの操作（インストール、削除など）にはここに表示された識別子を使用します。

### パッケージをアップグレードする

- 全てのパッケージをアップグレード（更新）したいときは以下のコマンドを実行します。

```shell
upgrade
```

- 指定したパッケージのみをアップグレードすることもできます。
  - この場合の動作は `install` コマンドと同様です。
- バージョンを固定したパッケージはアップグレードされません。

### パッケージを再インストールする

- パッケージを構成するファイルの一部を削除してしまったなどの理由により、パッケージを再インストールしたいときは以下のコマンドを実行します。

```shell
reinstall
```

- インストールされているすべてのパッケージに対して `remove` と `install` を自動的に行いますが、`remove` 時の依存関係チェックがスキップされます。
- 指定したパッケージのみを再インストールすることもできます。

### 最新のパッケージマニフェストを取得する

- BUtlerは起動時に自動的にパッケージマニフェストを更新しますが、手動で更新したいときは以下のコマンドを実行します。

```shell
update
```

- デフォルトでは、BUtlerの[コミュニティリポジトリ](https://github.com/Per-Terra/butler-pkgs)から情報を取得します。

## 利用可能なコマンド

### `help`

- 利用可能なコマンドを表示します。

### `list`

- インストール済みのパッケージを一覧表示します。

### `search <検索クエリ>`

- 利用可能なパッケージを検索して、一覧表示します。

### `show <パッケージ識別子>`

- 指定されたパッケージの詳細な情報を表示します。

### `install <パッケージ識別子>[=<バージョン>] [<パッケージ識別子>[=<バージョン>]]...`

- 指定されたパッケージをインストールします。
- バージョンを指定するとそのバージョンで固定され、アップグレードされることはありません。
- 例：[/AviUtlの推奨構成](https://scrapbox.io/aviutl/セットアップ)をインストールする

  ```shell
  install aviutl exedit=0.92 L-SMASH-Works InputPipePlugin easymp4 patch.aul
  ```

### `reinstall [<パッケージ識別子>]...`

- 指定されたパッケージを再インストールします。
- 何も指定しなければ全てのパッケージを再インストールします。

### `remove <パッケージ識別子> [<パッケージ識別子>]...`

- 指定されたパッケージを削除します。
- 設定ファイルは残ります。

### `purge <パッケージ識別子> [<パッケージ識別子>]...`

- 指定されたパッケージを設定ファイルを含めて完全に削除します。
- remove後でも実行できます。

### `autoremove`, `autopurge`

- 自動でインストールされたが、もはや必要でないパッケージを削除、または完全に削除します。

### `update`

- パッケージマニフェストを更新します。

### `upgrade [<パッケージ識別子>...]`

- パッケージ識別子を指定した場合の動作は `install` と同じです。
- パッケージ識別子を指定しなかった場合はインストールされた全てのパッケージをアップグレードします。

### `selfupdate`, `selfupgrade`

- BUtler自体の更新を確認、または適用します。

### `interactive`

- 対話型シェルを起動します。(コマンドを何も指定せず起動したときの既定値)
- デフォルトでは起動時に `selfupdate` と `update` を自動で実行します。
  - [設定](#設定)で変更可能です。

## 設定

`.butler/config.yaml` を編集することでBUtlerの動作を変更することができます。

### 項目

- `UseSymbolicLinks`：シンボリックリンクを使用するかどうか
  - `false` にセットした場合、ファイルは常にコピーされます。
  - 開発者モードを有効にしない場合、またはNTFS以外のファイルシステムを利用している場合は `false` にセットします。
- `Interactive.AutoSelfUpdate`：対話型シェル起動時に自動で `selfupdate` コマンドを実行するかどうか
- `Interactive.AutoUpdate`：対話型シェル起動時に自動で `update` コマンドを実行するかどうか

## 付録

### キャッシュについて

- `.butler/cache` はキャッシュフォルダーです。このフォルダーはいつ削除しても動作に問題はありません。容量を圧迫している際にお試しください。
- Windowsではジャンクションを作成することで別のフォルダーにキャッシュを保存することができます。
  - 複数のフォルダにBUtlerをインストールしていて、キャッシュを共通化したい場合に有効です。並列実行は考慮されていませんのでお気をつけください。

### 軽量にして持ち運ぶ

- `.butler/packages` フォルダー以下にはファイルの実体が含まれています。このフォルダーを削除してしまっても `reinstall` コマンドで復旧することができます。
- この仕様を利用して、 `.butler/cache` フォルダーと `.butler/packages` フォルダーを削除し、ZIP圧縮することで設定ファイルのみを持ったアーカイブを作成することができます。
  - この際、シンボリックリンクはZIPファイルの仕様上保持されません。
- アーカイブを展開したら、BUtlerを起動し `update` コマンドと `reinstall` コマンドを順に実行することで元の環境を復元することができます。

## ライセンス

[MIT License](LICENSE)に基づく
