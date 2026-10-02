# 言語リソースの追加調査（2026-10-03）

既出の gettext・Chrome 以外にも削減候補がある。個別ファイルとして分離されている追加候補は、OL10 で約181 MiB（展開時）。このうち .NET のサテライト DLL、Babel、Inkscape の言語別チュートリアルが大きい。

OL10 の全 rootfs では、既出の gettext・Chrome 整理に加えて約42.662 MiBを削減できた。

英語・日本語・ニュートラルを保持する方針で、3 OS の一時コンテナから他言語の独立リソースを取り除き、WSL rootfs の圧縮容量と機能を確認した。ソースマップ・Python バイトコード・Git デバッグ情報の整理は、今回の言語限定試行には含めていない。

## 測定対象

[先のサイズ削減調査](image-size-reduction-study.md)と同じ基準イメージを使用。

- OL9/10: コミット `d4a0999` の公開イメージに WSL 準備処理を適用したもの。
- OL8: 2026-09-30 のローカルイメージに今回の Python パッケージを追加した再現環境。CI と完全同一ではない。
- `/usr` と `/opt` を3 OSで走査。追加で DLL の CultureName、XML の `xml:lang`、Java モジュールの一覧、フォントの対応言語、呼び出し元コードを調べた。
- 全 rootfs は `podman export | gzip -9` で計測。機能確認は計測後に実施した。
- 保持判定は `en`・`ja` とその地域・スクリプト変種（`en-US`、`en_GB`、`ja_JP` など）。`root`・`C`・`POSIX` および各ツールの共通リソースも保持する。

## 個別ファイルとして整理した追加候補（OL10）

| 追加候補 | ファイル数 | 展開時 MiB | 候補単独の tar.gz MiB |
|---|---:|---:|---:|
| .NET SDK・MSBuild・Roslyn の翻訳 DLL | 1,512 | 65.934 | 17.221 |
| Inkscape の他言語チュートリアル・画像 | 233 | 82.316 | 15.481 |
| Babel の locale-data | 956 | 27.786 | 8.883 |
| 他言語 man ページ | 260 | 0.894 | 0.905 |
| 数式読み上げ用の他言語 mathmaps | 12 | 3.254 | 0.390 |
| MkDocs・Material の他言語検索データ | 54 | 0.543 | 0.097 |
| Material の UI 翻訳 | 67 | 0.147 | 0.039 |
| MkDocs 組み込みテーマの UI 翻訳 | 30 | 0.044 | 0.012 |
| Inkscape の他言語 default テンプレート | 70 | 0.043 | 0.003 |

「候補単独の tar.gz」は候補だけを別に tar/gzip した概算。全 rootfs からの削減量とは一致せず、単純加算して2 GiB判定には使わない。既出の gettext・Chrome はこの表に含めていない。

### 保持・削除の根拠

- **.NET**: 1,638 個の `*.resources.dll` を `AssemblyName.GetAssemblyName(...).CultureName` で検査。13 言語それぞれ126ファイルで、格納ディレクトリと CultureName が全件一致。日本語126個を保持し、他の12言語1,512個を削除した。ニュートラル・英語のメイン DLL は保持。`cs` ディレクトリ全体を削除すると C# 用の本体も消えるため、DLL 種別とメタデータによる限定が必要。[Microsoft のサテライトアセンブリ仕様](https://learn.microsoft.com/en-us/dotnet/core/extensions/create-satellite-assemblies)
- **Babel**: `locale-data/*.dat` の他言語956ファイルを削除。`root.dat`、全 `en*`・`ja*` を保持。`global.dat` は言語共通の地域・通貨・別名・親ロケール情報なので保持。保持した全ロケールについて継承データのロード、日付・通貨の書式を確認した。
- **Inkscape**: `tutorials/` と `templates/` の `名前.言語.svg/png` の他言語だけを削除。英語の無接尾辞ファイル、日本語、共通画像、`default.svg`、`default.ja.svg` を保持。残ったチュートリアル SVG の画像参照先も確認した。先の「チュートリアル全体を削除」と異なり、英語・日本語のチュートリアルを利用できる。
- **man**: 言語ディレクトリを対象に他言語だけを削除。`man1`〜`man9` などの言語共通・英語ディレクトリと `ja`・`ja_JP.UTF-8` は保持。man 個別圧縮は追加していない。
- **MkDocs・Material**: テーマの翻訳ディレクトリと `partials/languages/*.html` は `en`・`ja` を保持。Material の共通翻訳マクロは英語へフォールバックするため `en.html` を必ず残す。
- **検索**: 他言語の `lunr.言語.js` だけを削除。日本語は識別子が `ja` と `jp` の両方あるため両方を保持。`lunr.multi`、`lunr.stemmer.support`、`tinyseg.js`、検索本体・worker を保持。英語・日本語の Material サイトを検索プラグイン付きで生成して確認した。
- **数式読み上げ**: Speech Rule Engine の他言語 `lib/mathmaps/*.json` を削除。`base.json`・`en.json` と点字用の `euro.json`・`nemeth.json` は保持。点字規則は自然言語の翻訳とは異なる。読み上げ実装の JavaScript は保持し、英語の数式読み上げを確認した。

## 全 rootfs の実測

| OS | 基準 MiB | 言語整理後 MiB | 削減 MiB | 上限との差 MiB |
|---|---:|---:|---:|---:|
| OL8 | 2,143.621 | 2,048.253 | 95.368 | -0.253 |
| OL9 | 2,188.469 | 2,078.155 | 110.314 | -30.155 |
| OL10 | 2,095.332 | 1,983.178 | 112.154 | +64.822 |

上限との差が正なら余裕、負なら超過。OL8 は265,001 bytesの僅かな超過、OL9 は約30 MiB超過。言語整理だけでは全 OS を2 GiB未満にできない。先のソースマップ・バイトコード・Git デバッグ情報の整理と組み合わせる余地がある。組み合わせた全 rootfs は今回未測定。


## さらに残っている言語リソース

ここからは上記の全 rootfs 試行に含めていない。不要な他言語の翻訳があっても、同じファイルに共通コード・共通データが入っている場合は、ファイル丸ごとの削除では整理できない。

| 場所 | 調査結果 | 必要な処理・評価 |
|---|---|---|
| Java `lib/modules` | OL10 の `jdk.localedata` 内で他言語と識別できるリソースクラス約26.9 MiB（未圧縮）。他の Java モジュールにも翻訳クラスあり | モジュールの再構成が必要。`jlink --include-locales=en,ja` が公式に用意されるが、現 OL10 イメージは `jmods` がなく、実際の実行は失敗。開発用 JDK 全機能を保持する構成の検討が必要。下記公式資料参照 |
| MIME XML `/usr/share/mime` | 他言語の `xml:lang` 付き葉要素69,747個、889ファイル | XML 内の翻訳要素だけを削除する処理が候補。メモリ内の変換では約3.87 MiBの削減。各ファイルの gzip サイズ差の合計は約0.735 MiBで、全 rootfs の効果は未測定 |
| OS 情報 XML `/usr/share/osinfo` | 同様の翻訳葉要素31,277個、1,038ファイル | OS の識別・互換性情報を保持し翻訳名だけを削除。メモリ内の変換で約1.60 MiB、各ファイル gzip 差の合計約0.182 MiB。実ファイルへの適用・機能確認は未実施 |
| `.desktop` メニュー | 他言語の `Name[言語]` 等1,237行、約0.063 MiB | 言語付きキーのみ除去可能。`Exec`・`MimeType` 等の共通キーは保持 |
| X11 `/usr/share/X11/locale` | 明示的な他言語の国別ディレクトリ72ファイル、約0.229 MiB | `ja_JP.UTF-8/Compose` は英語 `en_US.UTF-8/Compose` を参照。英語・日本語・Cと共通エンコーディングを保持する必要がある。alias・参照関係を含めた変更の確認は未実施 |
| Droid 言語別フォント | `fc-query` で en・ja を含まないアラビア語・ヘブライ語・エチオピア語等12ファイル、計約0.896 MiB | 独立した追加候補。フォントキャッシュの再生成と英語・日本語・記号の表示確認が必要。CJK TTC は日本語を含むため保持 |
| Node.js Zod `locales/` | 他言語のエラーメッセージ実装を含む | `index.cjs` が全言語を eager require。アラビア語 `ar.cjs` だけを一時コピーから削除すると、既定言語でも `Cannot find module` で起動不能になることを再現。削除には参照コードの変更も必要 |
| React Aria の i18n、Speech Rule Engine の locale JS、バンドル内翻訳 | 翻訳と実装コードが同梱 | ファイル名だけでの削除は避け、import とバンドルの再構成まで検討する必要がある。今回の試行では維持 |

Java の限定オプションは [Oracle の jlink 仕様](https://docs.oracle.com/en/java/javase/21/docs/specs/man/jlink.html) を参照。`include-locales` は `jdk.localedata` を対象にするため、他モジュールのエラーメッセージ等を全部除去するオプションではない。

XML の「メモリ内の変換」は lxml で他言語の葉要素だけを除去し、シリアライズ後のサイズを比較したもの。シリアライズによる書式差も含み、インストール済みファイルは変更していない。

## 整理不要・保持対象

- glibc は3 OSの走査で英語・日本語・Cのロケールが中心。OL10 では `/usr/lib/locale/locale-archive.tmpl` は0 bytesで、大きな他言語 archive は見つからなかった。`en_HK`、`en_IN` などは英語の地域変種なので保持。
- PowerShell は OL10 で `en-US` のリソースが中心。他言語のサテライト DLL は見つからなかった。日本語 UI の要求時には利用可能な英語へフォールバックする。
- ICU、Unicode、文字コード変換表、PDF の CMap、CJK フォント、国・通貨コードの共通データは翻訳だけではなく日本語の処理でも使うため保持。
- `highlight.js/.../languages/` はプログラミング言語の定義。`.NET .../codestyle/cs`・`vb` も C#・Visual Basic の実装。自然言語の翻訳として削除しない。
- ライセンス・NOTICE・共通実装・画像・検索の基盤データは保持。言語名らしい短いディレクトリ名だけで汎用削除しない。

## 確認結果・再現情報

3 OS ですべて成功。

- `pip check`、MarkItDown の HTML 変換、Material・awesome-nav・callouts を使う MkDocs build。
- Babel の保持した126ロケール全件についてデータロード・日付・通貨の書式を確認。
- 英語・日本語の Material サイトを検索付きで厳格ビルド。ブラウザー上での検索操作までは確認していない。
- .NET の英語・日本語 CLI 情報表示、C# と Visual Basic の新規プロジェクト作成・オフライン restore・日本語 UI での build・実行。
- PowerShell の en-US・ja-JP UI culture 設定、日時表示・ヘルプ取得。
- Zod の起動・文字列検証、英語での数式読み上げ。
- Git の commit・clone・fsck・PCRE2、英語・日本語 man、Marp HTML、Mermaid SVG、Inkscape PNG、保持したチュートリアルの画像参照。

試行用 .NET テンプレートの言語名と C#/VB の標準出力の違いを修正して再確認した。初回の確認コードのエラーは製品側の不具合ではない。元の試行ログと修正後の確認ログを保存している。

3本の全 rootfs アーカイブも `gzip -t` で整合性を確認し、すべて成功した。

- 調査スクリプト・明細・ログ・実測アーカイブ: `/tmp/oracle-language-study-20261003/`
- 独立した一時コンテナで実施。基準イメージは保持。
- レポートはローカル調査資料。実装へ反映するときはインストール後に対象を限定した処理を置き、追加言語依存の参照と中立リソースの保持を継続して確認する。

## 実装への反映

検証済みの独立した言語リソースを `src/compact-image.py` に反映した。.NET の削除対象はメタデータ照合済みの12 culture の `*.resources.dll` に限定し、Lunr と数式読み上げも確認済みの言語識別子を列挙する。未知の共通リソースを既定で削除しない。各インストールと同じ RUN 内で処理し、`tests/verify-image-compaction.sh` を3 OSの CI に追加した。命名規則は AGENTS.md に記載し、命名の自動確認は追加していない。

組み合わせた実装の実測は [サイズ削減調査の実装結果](image-size-reduction-study.md#実装への反映) を参照。
