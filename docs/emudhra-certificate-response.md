# eMudhra 証明書問題への対応

調査日: 2026-10-25（追加対処・検証: 2026-10-26）。OL8/9/10 の x86_64 用配布リポジトリと、一時コンテナでの導入結果を記録します。既存コンテナやホストには適用していません。

## 対策版と導入可否

| コンポーネント | 対策版・配布状況 | このビルドでの対応 |
| --- | --- | --- |
| OS `ca-certificates` | 3 OS とも対策 RPM を取得・導入可能。下表参照 | 外部ツールの取得前に `2026.2.92_v9.0.319` 以上を必須とし、信頼ストアを再生成 |
| curl・Git・Python `ssl` | 標準設定では OS の CA ストアを使用 | OS 更新を適用。Git 本体のバージョン変更は不要 |
| Node.js 24 | upstream 24.22.1 に対策あり。OL10 の NodeSource から導入可能。OL8/9 の有効な AppStream は 24.21.0 まで | 配布元を維持し、全 OS で `NODE_OPTIONS=--use-openssl-ca` を指定。OL8/9 は OS ストアによる緩和策であり、upstream 対策版の導入とは区別する |
| pip | 26.2.2 が対策版。Python 3.12 に導入可能 | 公開 SHA256 を検証した wheel から 26.2.2 を導入。pip 内蔵の certifi も更新 |
| certifi | 2026.10.19 以降。調査時の取得版は 2026.10.23 | 最低版を指定し、実際の CA バンドルも検証 |
| `ensurepip` / 新規 `venv` | 配布版の初期 pip は OL8/9 が 23.2.1、OL10 が 23.3.2 | Python 3.12 の wheel 参照先へ pip 26.2.2 を配置。通常の `python -m venv` でも対策版が入ることを検証 |
| Java 21 / PlantUML | Oracle JDK には別途緊急更新あり。本イメージの OpenJDK RPM とは別製品。調査時の OpenJDK RPM は 21.0.12.1.1 | 既定の `cacerts` は OS が生成するストアへのリンク。OS 更新後に対象ルートがないことを検証 |
| NSS | upstream は 3.131.1。Oracle の取得可能な RPM は 3.124.0-5 系 | この構成の `libnssckbi.so` は `p11-kit-trust.so` を参照。OS 更新で対処し、リンク先も検証 |
| gh | 最新 2.103.2 の配布 RPM は Go 1.27.3 製 | 2.101.0 から 2.103.2 へ更新。OL8/9/10 でバイナリの起動を確認 |
| glab | 最新 1.124.0 の配布 RPM も Go 1.27.2 製。Go の対策版 1.27.3 / 1.26.10 による再ビルド版とは確認できない | バージョンは維持。標準 OS ストアを使う TLS 接続は OS 更新で対処。Go 内蔵の中間鍵ブロック追加は未反映として追跡 |
| Podman など Go 製 RPM | Go 本体の更新だけでは、既存バイナリに修正は入らない | OS ストアの更新を適用。各 RPM の Go 修正取り込み状況は個別のアドバイザリで判断する |
| .NET / PowerShell の HTTPS | Linux の既定 TLS 検証は OS ストアに依存 | OS 更新の対象。SDK 同梱の署名検証用バンドルも対象ルートを除外 |
| Chrome for Testing / Puppeteer / Mermaid / Marp | 最新 Stable の 156.0.8078.47 は OL8 でも起動可能。しかし後述の検証では問題のチェーンを受け入れた | 最新化だけを対処済みとせず、今回のバージョンは維持し、公式 `CADistrustedCertificates` ポリシーで対象ルートの鍵を明示的不信頼化 |

OS の導入確認済み RPM:

| OS | `ca-certificates` |
| --- | --- |
| OL8 | `2026.2.92_v9.0.319-81.3.el8_10` |
| OL9 | `2026.2.92_v9.0.319-90.3.el9_8` |
| OL10 | `2026.2.92_v9.0.319-100.3.el10_2` |

Oracle の公開情報は [Errata 一覧](https://linux.oracle.com/ords/f?p=1105:21) から ELSA-2026-88550 / 88459 / 88455 を参照してください。10 月 20 日の初回対策より新しいパッケージを採用しています。

## ビルドと検証

`src/Dockerfile` の初期パッケージ処理で CA の最低版を指定します。最低版を取得できない場合はビルドが失敗します。一般的な全パッケージ更新は追加していません。

Node.js の `--use-system-ca` は同梱 CA に OS CA を追加する機能のため、古い同梱 CA を除外する用途には使いません。`--use-openssl-ca` により OS ストアへ切り替えます。この環境変数は npm や Node.js 製ドキュメントツールにも適用されます。

アプリケーションが `NODE_OPTIONS` を上書きする場合は、この指定も維持してください。独自に指定した CA バンドルや Java truststore は今回の既定ストアの更新対象に含みません。

pip は更新済み OS ストアを使用する curl で wheel を取得し、Python セキュリティチームが公開した SHA256 と照合してからローカルインストールします。OL8/9 の OS 用 Python とは別の `/usr/share/python3.12-wheels`、OL10 は `/usr/share/python3-wheels` に保存し、標準ライブラリの書き換えは行いません。

ビルド時と CI で `python -B /usr/local/libexec/verify-ca-trust.py` を実行します。OS / Python ssl、certifi、pip 同梱 certifi、Java cacerts の実データを SHA256 で確認し、Node.js と NSS の参照先、新規 venv の初期 pip も検証します。追加で .NET SDK の全 `trustedroots/*.pem` と Chrome のポリシー内容も照合します。CI では Node.js / Chrome の実接続と正常な NuGet パッケージの署名検証も行います。

今回の動作検証は既存ローカルイメージを基にした一時コンテナで、関連パッケージの導入と設定を行いました。リポジトリ全体のイメージ再ビルドは実施していません。起動済みコンテナや永続化ホームにある venv、ユーザー導入ランタイムは別途更新が必要です。

OL8/9/10 で上記のオフライン検証に成功しました。追加の接続試験では、Node.js が正常な Google HTTPS 接続に成功し、検証用の通常経路・AAA クロス署名経路と各 No CT 経路の計 4 通りを証明書エラーで拒否しました。ネットワーク障害を証明書拒否として数えていません。

## 追加した独立ストア対策

### Chrome for Testing

新規プロファイル、Puppeteer Core、Headless、通常の証明書検証を有効にした構成で確認しました。156.0.8078.47 は、正常な Google HTTPS 接続に成功した後、公開検証用の `https://dv-g3b-emudhra.we-have-a-problem.com/` にも接続しました。OS の CA 更新後も同じ結果でした。検証の最初の問題チェーンで失敗したため、残る 13 通りの保護状況は未判定です。

ブラウザーの CRLSet / Chrome Root Store は OS ストアと別管理です。通常の Chrome への失効情報配信を、そのまま新規プロファイルの CFT / 自動化環境の保護と見なすことはできません。Google はルート削除の全端末向け配信を 10 月 27 日 PDT に予定しています。本ビルドでは配信を待たず、CFT の `/etc/opt/chrome_for_testing/policies/managed/emudhra.json` に `CADistrustedCertificates` を設定します。これは証明書の SPKI を照合する公式ポリシーで、同じ鍵のクロス署名も不信頼化します。設定後は、現行 Chrome 153 を使う OL8/9/10 で 14 通りのチェーンすべてが証明書エラーで拒否され、正常な HTTPS 接続にも成功しました。証明書検証は無効化していません。

### .NET SDK の同梱ストア

ローカルイメージにある SDK 10.0.112 の `trustedroots/timestampctl.pem` には、OS 更新後も `emSign ECC Root CA - G3` と `AAA Certificate Services` が残っていました。これは NuGet のタイムスタンプ署名検証用で、HTTPS 用ストアとは別です。このバンドルを更新する .NET の対策リリースを確認できていないため、ビルド時に `ca_distrust.py` で対象ルートを除外します。既存の証明書を SHA256 で照合し、他の証明書を保持します。空のバンドルや想定外の形式はビルドエラーとします。OL8/9/10 で除外後も Newtonsoft.Json 13.0.3 の作者・リポジトリ署名が `dotnet nuget verify --all` に成功しました。これは正常署名の互換性確認であり、タイムスタンプ偽造の成立を判定したものではありません。

### 再適用と対象範囲

コンテナ内で .NET SDK を追加・更新するとバンドルが再導入されるため、`sudo python -B /usr/local/libexec/ca_distrust.py` を再実行し、`python -B /usr/local/libexec/verify-ca-trust.py` で確認してください。除外対象ルートに依存する正規の接続や署名も拒否されます。

### OS 用 Python と既存の仮想環境

更新対象は既定の開発用 Python 3.12 です。OL8 の platform-python や OL9 の OS 用 Python 3.9 に属する古い pip、独自 venv 内の pip / certifi には波及しません。OS 用 Python のパッケージ管理設定は変更していません。

## 公式情報

- [Node.js 24.22.1 リリース](https://nodejs.org/en/blog/release/v24.22.1): CA 更新とブロック対象公開鍵の拒否を含む。
- [Python セキュリティチームの案内](https://discuss.python.org/t/information-for-python-users-regarding-emudhra-emsign-ca-certificate-security-incident/109576): pip / certifi の最低版と bootstrap wheel の SHA256。
- [pip changelog](https://pip.pypa.io/en/stable/news/): 26.2.2 で内蔵 certifi を更新。
- [Oracle Java の案内](https://ops.java/emudhra): Oracle JDK の更新と独立ストアの扱い。
- [Go リリース履歴](https://go.dev/doc/devel/release): Go 1.27.3 / 1.26.10。
- [gh 2.103.2](https://github.com/cli/cli/releases/tag/v2.103.2)、[glab 1.124.0](https://gitlab.com/gitlab-org/cli/-/releases/v1.124.0): 配布 RPM の Go バージョンをバイナリ内のビルド情報で確認。
- [Google のインシデント案内](https://blog.google/security/protecting-chrome-and-android-users-from-compromised-emudhra-intermediate-ca-certificates/)、[Chromium の Root Store FAQ](https://chromium.googlesource.com/chromium/src/+/main/net/data/ssl/chrome_root_store/faq.md): OS とは独立した更新経路。
- [検証サイト・チェーン一覧](https://emudhra.we-have-a-problem.com/): 対象ルートの SHA256 と検証用エンドポイント。

- [Chrome 不信頼ポリシーの公式スキーマ](https://raw.githubusercontent.com/chromium/chromium/main/components/policy/resources/templates/policy_definitions/CertificateManagement/CADistrustedCertificates.yaml)、[CFT の Linux ポリシーパス](https://raw.githubusercontent.com/chromium/chromium/main/components/policy/core/common/policy_paths.cc)。
