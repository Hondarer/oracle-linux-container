# rootfs サイズ削減のローカル試行（2026-10-03）

既存の `.tar.gz` 配布を維持するなら、日本語・英語以外の翻訳、Node.js ソースマップ、Python バイトコード、Git のデバッグ情報の整理が有効。3 OS で約165〜173 MiB削減し、2 GiB未満になった。man の個別 gzip 圧縮は配布アーカイブを約0.4 MiB増やしたため、最終候補から除外した。

OL9 の最終候補には約33 MiBの余裕しかない。更新時の増加に備える場合は付属ドキュメント・Inkscape チュートリアルの整理、または配布圧縮形式の変更を追加候補とする。

## 測定条件

- 上限: 2,147,483,648 bytes 未満（2,048 MiB）。比較対象は WSL rootfs の圧縮アーカイブ。
- OL9/10: コミット `d4a09994e1a0d75843444e02e8d9c580db56beda` の公開イメージ `sha-d4a0999` を取得し、リポジトリの WSL 準備スクリプトで派生イメージを作成した。
- OL8: CI がキャンセルされ新イメージが公開されていないため、2026-09-30 のローカルイメージに今回の4パッケージと `markitdown[all]==0.1.8` を追加して再現。OL8 の値はこの再現イメージの実測であり、CI と同一とは保証しない。
- 基準と各試行は同じ WSL ベースイメージから別の一時コンテナとして作成。圧縮前に変更を適用し、`podman export` の全出力を `gzip -9` で圧縮した。
- 機能確認は容量計測後に実施し、確認用ファイルや再生成された `.pyc` が計測に混入しない順序とした。
- OL10 の基準値は2,197,114,546 bytes。CI の2,197,151,391 bytesとの差は36,845 bytes（約36 KiB）。ローカルのユーザー作成時刻・コンテナ設定などの差は残る。
- 単独施策は OL10 で比較し、組み合わせを3 OSで比較。施策の実行順や tar の配置によって圧縮率が変わるため、削減量は単純加算できない。

## 単独施策（OL10、全 rootfs の gzip サイズ）

| 施策 | 圧縮後 MiB | 基準からの削減 MiB | 2 GiB未満 |
|---|---:|---:|---|
| 基準 | 2,095.332 | 0.000 | 超過 |
| man の gzip 圧縮 | 2,095.726 | -0.395 | 超過 |
| 日本語・英語以外の翻訳整理（Chrome を含む） | 2,025.840 | 69.492 | 成功 |
| Node.js ソースマップ整理 | 2,058.261 | 37.071 | 超過 |
| Python .pyc 整理 | 2,057.320 | 38.012 | 超過 |
| Git のデバッグ情報削除 | 2,074.700 | 20.632 | 超過 |
| Inkscape チュートリアル整理 | 2,078.709 | 16.623 | 超過 |
| 付属ドキュメント整理 | 2,059.061 | 36.271 | 超過 |

翻訳は `/usr/share/locale`、`/usr/local/share/locale`、`/opt/inkscape/usr/share/locale` の `ja*`、`en*`、`C`、`POSIX` を保持し、Chrome は `ja`、`en-US`、`en-GB` を保持した。glibc の locale archive は変更していない。

ソースマップは `/usr/local/lib/node_modules` 配下の `.js.map`、`.mjs.map`、`.css.map` を対象とした。Python は対応する `.py` が存在する `.pyc` だけを削除。ソースなしのバイトコードは対象外。

Git は `/usr/local/bin/git` と `/usr/local/libexec/git-core` の ELF ファイルから `strip --strip-debug` でデバッグ情報のみ削除した。初回の試行は inode ごとの一度の処理と元ファイルへの書き戻しを使ったが、後続の実装検証で overlayfs の copy-up によって一部のハードリンクが分かれることを確認した。以下の初回実測はその状態を含む。実装では処理前にコマンドの全 alias を収集し、必要時に同じ inode へ再リンクする方式へ修正した。

付属ドキュメント施策は `/usr/share/doc`、`/usr/local/share/doc` の通常ファイルを選別。LICENSE/LICENCE/COPYING/COPYRIGHT/NOTICE/AUTHORS を名前に含むファイル、当リポジトリの配布ドキュメント、`/usr/share/licenses`、man を保持した。恒久導入時には各パッケージで必要な文書をさらに選別する。

## 組み合わせ（3 OS）

| 構成 | OL8 MiB | OL9 MiB | OL10 MiB |
|---|---:|---:|---:|
| 基準 | 2,143.621 | 2,188.469 | 2,095.332 |
| 翻訳 + .pyc + Git debug + man 圧縮 | 2,013.434 | 2,052.595 | 1,967.707 |
| 上記 + ソースマップ | 1,976.384 | 2,015.540 | 1,930.655 |
| 最終候補: 翻訳 + .pyc + Git debug + ソースマップ | 1,975.954 | 2,015.069 | 1,930.257 |
| 最終候補 + 付属文書 + チュートリアル + man 圧縮 | 1,911.507 | 1,953.169 | 1,877.734 |

最終候補の詳細:

| OS | 圧縮後 bytes | 削減 MiB | 上限までの余裕 MiB |
|---|---:|---:|---:|
| OL8 | 2,071,938,382 | 167.666 | 72.046 |
| OL9 | 2,112,952,679 | 173.400 | 32.931 |
| OL10 | 2,024,020,768 | 165.075 | 117.743 |

OL9 はソースマップを残した組み合わせで2,052.595 MiBとなり、4.595 MiB超過した。ソースマップ整理を含めた最終候補では2,015.069 MiBとなった。

追加の付属文書・チュートリアル整理は OL9 の余裕を約95 MiBまで広げた。ただし、この追加試行には man 圧縮も含む。恒久実装では man 圧縮を除いた構成で最終サイズを確認する。

## 圧縮方式の比較（OL10 基準、ファイル削除なし）

同一の基準 tar を再圧縮した比較。内容を削除しない方式。処理時間には元の gzip アーカイブの展開が含まれ、並行負荷もあるため純粋な圧縮速度のベンチマークではない。

| 方式 | 圧縮後 MiB | gzip -9 比の削減 MiB | 再圧縮時間 秒 |
|---|---:|---:|---:|
| pigz-9（8並列） | 2,092.330 | 3.002 | 121.1 |
| xz-6（8並列） | 1,494.059 | 601.273 | 577.5 |
| zstd-19（8並列） | 1,600.282 | 495.050 | 671.9 |

`pigz -9` は gzip 形式を保つが、単独では2 GiBを超過した。`xz -6` と `zstd -19` は大きく削減できたが、既存の `.tar.gz` 配布・検証処理の変更が必要。Windows 側での直接インポートは今回未確認。採用するなら tar に復元して既存のインポート手順を使う経路も検討する。[Microsoft の tar インポート手順](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro)

## 機能確認・整合性

- 22構成のすべてでパッケージ依存関係、MkDocs Material + awesome-nav + callouts + superfences のサイト生成、MarkItDown の HTML 変換、Git の commit/clone/fsck/PCRE2、man 表示、Marp HTML、Mermaid SVG、Inkscape PNG を確認し、成功した。
- 最終候補の3 OSで既存の `tests/verify-git.sh` を実行し、HTTP clone・一般ユーザー・補完・システム設定を含む統合テストが成功した。Git debug 単独施策の OL10 でも同じ統合テストが成功。
- 最終候補の3 OSで一般ユーザーによる日本語 Marp PDF 生成、および MarkItDown による PDF/DOCX/PPTX/XLSX の変換が成功した。
- OL10 の日本語 SVG → PNG 変換は、基準と最終候補の RGBA ピクセル SHA256 が一致。既存の Inkscape/glibmm/font 警告は基準・最終候補の両方にあり、追加試行も成功した。
- 25アーカイブすべてで `gzip -t` / `xz -t` / `zstd -t` が成功した。
- Windows 上の WSL インポート、GUI 全体、多言語での利用、Azure 接続・音声認識など外部サービスを使う機能は未確認。

## 利用上の影響と推奨

1. `.tar.gz` 維持の第一候補は最終候補の4処理。man、ヘッダー、静的ライブラリ、言語ランタイム、追加した Python パッケージ、ライセンス類を保持する。
2. 翻訳整理で日本語・英語以外のメッセージ表示が減る。ソースマップ整理でツール自身の例外を元の JS/TS に対応させにくくなる。Git debug 整理で Git 自体のソースデバッグ情報が減る。
3. `.pyc` は起動・import 時に再生成される。配布サイズには効くが、稼働後のディスク容量は増え得る。初回 import の時間増加は今回定量測定していない。
4. OL9 の約33 MiBの余裕は更新によって消費され得る。追加の付属文書・チュートリアル整理、または `.xz` 配布で余裕を確保する案を検討する。
5. man の個別圧縮は配布サイズ削減の対象から除外する。試行では man を読めたが、既存 Git テストが期待する未圧縮ファイルのパスを変えるため、採用時にはテストの変更も必要。
6. OCI レジストリのレイヤー容量も減らすなら、各インストールと同じ RUN 内で整理する。WSL の圧縮 rootfs 対策としては WSL 準備処理での整理も有効。

## データ・再現手順

- 詳細な実測値: [CSV](./261003-image-size-reduction-study.csv)。
- 一時アーカイブ、対象ファイル一覧、ログ、スクリプト: `/tmp/oracle-size-study-20261003/`。
- `cleanup.py`: 各施策の実装。`run-study.py`: 一時コンテナ・export・圧縮・機能確認。
- `smoke.sh` / `extra-smoke.sh` / `run-extra.py`: 機能確認。`compress-study.py`: 圧縮方式比較。`verify-study.py`: アーカイブ整合性確認。
- `*-files.json`: 実際に整理したファイルとサイズ。`*-result.json`: 各試行のサイズ・終了コード。
- 再実行時は既存の試行コンテナ名との衝突を避けるか、試行専用コンテナを削除してから実行する。

```bash
python3 /tmp/oracle-size-study-20261003/run-study.py 10
python3 /tmp/oracle-size-study-20261003/run-study.py 9 baseline combined-conservative combined-recommended combined-extended
python3 /tmp/oracle-size-study-20261003/run-study.py 8 baseline combined-conservative combined-recommended combined-extended
python3 /tmp/oracle-size-study-20261003/run-study.py 10 combined-final
python3 /tmp/oracle-size-study-20261003/run-study.py 9 combined-final
python3 /tmp/oracle-size-study-20261003/run-study.py 8 combined-final
```

測定元イメージ:

- OL10: `ghcr.io/hondarer/oracle-linux-container/oracle-linux-10-dev@sha256:d99a1bd5293743c2678665a8247411906ceaa882225c3fa83d0f8822c97cead4`
- OL9: `ghcr.io/hondarer/oracle-linux-container/oracle-linux-9-dev@sha256:ecb049561be03049bc8f9ba3b4c047ee07fa299506563e21990b6e6d4f0c52aa`
- OL8 再現元: `localhost/oracle-linux-8@sha256:ddb743a9346f561acf52f4433028f6682a017de64864caf7fd399a27e615b3da`

本調査では Dockerfile・WSL 準備処理・CI 設定の恒久変更は行っていない。

## 言語リソースの追加調査

.NET の翻訳 DLL、Babel、他言語の Inkscape チュートリアル・man・MkDocs 検索データ等も見つかった。OL10 では、gettext・Chrome の整理に追加して全 rootfs の gzip を約42.662 MiB減らせた。[追加調査の実測と保持条件](261003-image-language-resource-study.md)を参照。

## 実装への反映

`src/compact-image.py` を各インストールと同じ RUN 内で呼び出す。先の4施策に、検証済みの .NET・Babel・Inkscape・man・MkDocs・数式読み上げの他言語リソース整理を追加した。Git は overlayfs の copy-up 後も alias を再リンクして保持し、統合テストで確認する。Java 再構成・XML 内翻訳・フォント選別・付属文書の一括削除・man 個別圧縮は採用していない。

実装した3段階の処理を新しい一時コンテナへ適用し、3 OS で `verify-image-compaction.sh`、既存 Git 統合テスト、MkDocs・Marp・Mermaid・Inkscape、MarkItDown の PDF/DOCX/PPTX/XLSX 変換がすべて成功した。Git の150個のコマンド別ハードリンクの保持も確認した。

容量が最も厳しかった OL9 は機能確認前の全 rootfs を測定した。

| OS | 圧縮後 bytes | 圧縮後 MiB | 基準からの削減 MiB | 2 GiBまでの余裕 MiB |
|---|---:|---:|---:|---:|
| OL9 | 2,041,177,515 | 1,946.619 | 241.851 | 101.381 |

`gzip -t` も成功。OL8/10 は今回の実装について機能確認を実施し、圧縮容量の再計測は CI で確認する。実装検証のスクリプト・アーカイブ・ログは `/tmp/oracle-image-compaction-v2-20261003/` に保存した。本番と同じ読み取り専用 RUN マウント形式での派生ビルドと、そのイメージの統合テストも成功した。
