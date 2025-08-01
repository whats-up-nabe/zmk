# roBa ローカルビルド手順 (Docker + VSCode)

roBaファームウェアをGitHub Actionsを使わず、ローカルPC上のDockerコンテナを利用してビルドするための手順です。

この方法により、コンテナや一部の中間ファイルを再利用できるため、GitHub Actionsを使用するよりもビルド時間を短縮できます。また、ビルド成果物のダウンロードや解凍の手間も省けます。

**主なビルド方法として、GitHub上のあなたの `zmk-config-roBa` リポジトリを直接参照する方法 (推奨) と、従来通りローカルの `zmk-config-roBa` ディレクトリを参照する方法の2通りを説明します。**

## 日常的なビルドフロー（まとめ）

一度環境構築が完了した後の、日常的なファームウェア更新・ビルド作業は以下の流れで行います。

1.  **ソースコードの最新化 (ホストOSのターミナル):**
    *   `zmk` 本体リポジトリを最新化します。
        ```sh
        cd /path/to/your/zmk  # zmkリポジトリのローカルパス
        git checkout main      # mainブランチに切り替え (必要に応じて)
        git pull origin main   # リモートの最新を取得
        ```
    *   **キーマップ等をWebエディタ等で編集し、GitHub上の `zmk-config-roBa` リポジトリにPushした場合、以下のローカル `zmk-config-roBa` の更新は不要です。**
        ローカルの `zmk-config-roBa` ディレクトリを直接編集して `./build_all_local.sh` でビルドする場合は、従来通り最新化してください。
        ```sh
        # (ローカル参照ビルド ./build_all_local.sh を使用する場合のみ)
        # cd /path/to/your/zmk-config-roBa  # zmk-config-roBaリポジトリのローカルパス
        # git checkout main                 # mainブランチに切り替え (必要に応じて)
        # git pull origin main              # リモートの最新を取得 (ご自身のフォーク元のリモートを指定)
        ```

2.  **VSCodeでコンテナ環境を開く:**
    *   ホストOSで、最新化した `zmk` ディレクトリをVSCodeで開きます。
    *   コマンドパレットから `Remote-Containers: Reopen in Container` を実行し、Dev Container環境に接続します。
        *   もしコンテナイメージの更新が促された場合は、リビルドしてください。

3.  **依存関係の更新 (コンテナ内ターミナル):**
    *   VSCode内のターミナル (`/workspaces/zmk` がカレントディレクトリ) で、以下のコマンドを実行して、ZMKの依存関係やサブモジュール (リモートの `zmk-config-roBa` を含む) を最新化します。
        ```sh
        west update
        ```
        **このコマンドにより、`app/west.yml` に基づいて、あなたのGitHub上の `zmk-config-roBa` リポジトリの最新版 (指定されたブランチ) がコンテナ内に取得されます。**

4.  **ファームウェアの一括ビルド (コンテナ内ターミナル):**
    *   VSCode内のターミナルで、利用したいビルドスクリプトを実行します。
        *   **推奨: リモートの `zmk-config-roBa` を参照してビルド (キーマップエディタ等での変更を反映):**
            ```sh
            ./build_all.sh
            ```
        *   **従来通り: ローカルの `zmk-config-roBa` を参照してビルド (Dockerボリューム経由):**
            ```sh
            ./build_all_local.sh
            ```
    *   ビルドが完了すると、成果物 (`.uf2` ファイル) が `/workspaces/zmk-config/config/build/` (ホストOSの `zmk-config-roBa/config/build/`) に出力されます。

5.  **ファームウェアの書き込み:**
    *   各マイコンをブートローダーモードで起動し、対応する `.uf2` ファイルを書き込みます。

---

以上で、roBaファームウェアのローカルビルド手順は完了です。

## 前提環境

*   macOS (Apple M1)
*   Docker Desktop
*   Visual Studio Code
*   VSCode拡張機能: Remote - Containers

## 公式ドキュメント

より詳細な情報や他の環境でのビルド方法については、以下の公式ドキュメントを参照してください。

*   [ZMK公式: 環境構築 (コンテナ)](https://zmk.dev/docs/development/local-toolchain/setup/container)
*   [ZMK公式: ビルドとフラッシュ](https://zmk.dev/docs/development/local-toolchain/build-flash)

## 環境構築 (初回のみ)

ここからの手順は、基本的に初回環境構築時のみ必要です。

### 1. リポジトリのクローン

作業用のディレクトリを作成し、その配下に以下のリポジトリをクローンします。

例: `/Users/your_username/dev/zmk-local-build/` を作業ディレクトリとする場合

*   **ZMK本体:**
    ```sh
    git clone https://github.com/zmkfirmware/zmk.git
    ```
    (クローン先: `/Users/your_username/dev/zmk-local-build/zmk`)

*   **ユーザー設定リポジトリ (roBa) - ローカル参照ビルド用:**
    `./build_all_local.sh` を使用する場合や、ビルド成果物の出力先として、ローカルにもクローンしておきます。
    あなたの `zmk-config-roBa` リポジトリをクローンします。URLはご自身のものに置き換えてください。
    ```sh
    git clone https://github.com/whats-up-nabe/zmk-config-roBa.git
    ```
    (クローン先: `/Users/your_username/dev/zmk-local-build/zmk-config-roBa`)

### 2. ツールのインストール

*   Docker Desktop をインストールします。
*   Visual Studio Code をインストールします。
*   VSCodeの拡張機能 `Remote - Containers` (ms-vscode-remote.remote-containers) をインストールします。

### 3. Dockerボリュームとコンテナの準備

#### a. zmk-config用Dockerボリュームの作成

**ビルド成果物の出力先として、また `./build_all_local.sh` でローカルのユーザー設定リポジトリを参照するために、Dockerボリュームを作成します。**
ユーザー設定リポジトリ (`zmk-config-roBa`) をコンテナ内にマウントするためのDockerボリュームを作成します。
ターミナルで以下のコマンドを実行します。`/absolute/path/to/your/zmk-config-roBa` は、先ほどクローンした `zmk-config-roBa` ディレクトリへの絶対パスに置き換えてください。

```sh
docker volume create --driver local -o o=bind -o type=none -o device="/absolute/path/to/your/zmk-config-roBa" zmk-config
```

例:
```sh
docker volume create --driver local -o o=bind -o type=none -o device="/Users/your_username/dev/zmk-local-build/zmk-config-roBa" zmk-config
```

#### b. ZMK用コンテナの作成と起動

1.  クローンしたZMK本体のリポジトリ (`zmk` ディレクトリ) をVSCodeで開きます。
2.  VSCodeのコマンドパレット (Cmd+Shift+P または Ctrl+Shift+P) を開き、「Remote-Containers: Reopen in Container」を実行します。
3.  コンテナイメージのビルドと起動が開始されます。完了すると、VSCodeがコンテナ内の `/workspaces/zmk` ディレクトリを開いた状態で再接続されます。

以降のコマンドは、特に指示がない限り、このVSCodeのコンテナ内ターミナル (`/workspaces/zmk` がカレントディレクトリ) で実行します。

#### c. West update の実行
設定ファイルを編集後 (主に `app/west.yml` で `zmk-config-roBa` のリモートリポジトリ情報を設定した場合)、コンテナ内のターミナルで以下のコマンドを実行し、依存関係とカスタムモジュールをダウンロード・更新します。
```sh
west update
```
これにより、`zmk-pmw3610-driver` や、`app/west.yml` で指定された `zmk-config-roBa` がコンテナ内の指定パス (例: `/workspaces/zmk/modules/config/zmk-config-roBa/`) にダウンロードされます。

## ビルド

ビルドは全てコンテナ内の `/workspaces/zmk` ディレクトリで行います。
日常的には上記の「日常的なビルドフロー（まとめ）」の通り、一括ビルドスクリプトの使用を推奨します。

### ビルドスクリプトによる一括ビルド

3つのファームウェア (右手用、左手用、リセット用) を並行してビルドし、成果物を `/workspaces/zmk-config/config/build/` (ホストOSでは、`zmk-config-roBa` ディレクトリ内の `config/build/`) に自動で保存するスクリプトが `/workspaces/zmk/` に配置されています。

*   **`./build_all.sh`**:
    GitHub上のあなたの `zmk-config-roBa` リポジトリ ( `app/west.yml` で設定されたもの) を参照してビルドします。キーマップエディタ等でリモートリポジトリを更新した場合にこちらを使用します。
    ```sh
    ./build_all.sh
    ```
*   **`./build_all_local.sh`**:
    従来通り、Dockerボリュームでマウントされたローカルの `zmk-config-roBa` ディレクトリを参照してビルドします。ローカルで直接ファイルを編集して試す場合などに使用します。
    ```sh
    ./build_all_local.sh
    ```

スクリプトは以下の処理を行います:
1.  各シールドのビルドディレクトリをクリーンアップします (`rm -rf build/roba_r` など)。
2.  右手用、左手用、リセット用のファームウェアを並行してビルドします。
3.  ビルドログは `/workspaces/zmk/build_logs/` 配下に保存されます。
4.  全てのビルドが成功すると、生成された `.uf2` ファイルが、ファイル名にボード名とシールド名を含めた形で `/workspaces/zmk-config/config/build/` ディレクトリにコピーされます。
    *   例: `roBa_R-seeeduino_xiao_ble-zmk.uf2`
5.  コピー先に同名ファイルが存在する場合、既存のファイルはタイムスタンプ付きのバックアップディレクトリに移動されます。
6.  いずれかのビルドが失敗した場合、エラーメッセージとログファイルの場所が表示され、成果物のコピーは行われません。

### （補足）個別ビルド (手動)

特定のファームウェアのみを個別にビルド・テストしたい場合は、以下のコマンドを使用できます。
ビルド成果物 (.uf2ファイル) は、各ビルドディレクトリ内の `zephyr/zmk.uf2` として生成されます。

#### リモートリポジトリ参照 (`./build_all.sh` と同様の参照)

**右手用 (roBa_R)**
```sh
west build -s app -b seeeduino_xiao_ble -d build/roba_r -- -DSHIELD=roBa_R -DZMK_CONFIG=/workspaces/zmk/modules/config/zmk-config-roBa/config -DSNIPPET=studio-rpc-usb-uart -DZMK_EXTRA_MODULES=/workspaces/zmk/modules/config/zmk-config-roBa
```

**左手用 (roBa_L)**
```sh
west build -s app -b seeeduino_xiao_ble -d build/roba_l -- -DSHIELD=roBa_L -DZMK_CONFIG=/workspaces/zmk/modules/config/zmk-config-roBa/config -DZMK_EXTRA_MODULES=/workspaces/zmk/modules/config/zmk-config-roBa
```

**リセット用 (settings_reset)**
```sh
west build -s app -d build/settings_reset -b seeeduino_xiao_ble -- -DSHIELD=settings_reset -DZMK_CONFIG=/workspaces/zmk/modules/config/zmk-config-roBa/config -DZMK_EXTRA_MODULES=/workspaces/zmk/modules/config/zmk-config-roBa
```

#### ローカルディレクトリ参照 (`./build_all_local.sh` と同様の参照)

**右手用 (roBa_R)**
```sh
west build -s app -b seeeduino_xiao_ble -d build/roba_r_local -- -DSHIELD=roBa_R -DZMK_CONFIG=/workspaces/zmk-config/config -DSNIPPET=studio-rpc-usb-uart -DZMK_EXTRA_MODULES=/workspaces/zmk-config
```

**左手用 (roBa_L)**
```sh
west build -s app -b seeeduino_xiao_ble -d build/roba_l_local -- -DSHIELD=roBa_L -DZMK_CONFIG=/workspaces/zmk-config/config -DZMK_EXTRA_MODULES=/workspaces/zmk-config
```

**リセット用 (settings_reset)**
```sh
west build -s app -d build/settings_reset_local -b seeeduino_xiao_ble -- -DSHIELD=settings_reset -DZMK_CONFIG=/workspaces/zmk-config/config -DZMK_EXTRA_MODULES=/workspaces/zmk-config
```
(注: ローカル参照時のビルドディレクトリ名を `_local` 付きに変更して、リモート参照ビルドと区別できるようにしました。)

変更があったファイルのみ再コンパイルされます。ただし、KconfigやCMakeの変更があった場合は、フルビルドが必要になることがあります。その際は、一度 `build/ビルド名` ディレクトリを削除するか、上記のフルビルドコマンドを再実行してください。

## ファームウェアのフラッシュ

ビルドスクリプトを使用した場合、ファームウェア (`.uf2` ファイル) はホストOSの `zmk-config-roBa/config/build/` ディレクトリに出力されます。
各マイコンをブートローダーモードで起動し、対応する `.uf2` ファイルをドラッグアンドドロップして書き込んでください。
