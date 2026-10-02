#!/bin/bash
# 一時コンテナ内で root として実行。保持した en/ja と共通リソースを検証する。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
COMPACTION_TEST_DIR="$(mktemp -d /tmp/compaction-test.XXXXXX)"
trap 'rm -rf "$COMPACTION_TEST_DIR"' EXIT

python -B - <<'PY'
from datetime import date
from pathlib import Path
from babel import localedata
from babel.dates import format_date
from babel.numbers import format_currency
from lxml import etree

locales = localedata.locale_identifiers()
assert 'en' in locales and 'ja' in locales
assert all(name.split('_')[0] in ('en', 'ja') for name in locales)
assert localedata.load('root')
for name in locales:
    localedata.load(name)
    format_date(date(2026, 10, 3), locale=name)
    format_currency(1234, 'JPY', locale=name)
print('Babel retained locale checks passed:', len(locales))

root = Path('/opt/inkscape/usr/share/inkscape')
assert (root / 'templates/default.svg').is_file()
assert (root / 'templates/default.ja.svg').is_file()
assert (root / 'tutorials/tutorial-basic.svg').is_file()
assert (root / 'tutorials/tutorial-basic.ja.svg').is_file()
for path in (root / 'tutorials').glob('*.svg'):
    for element in etree.parse(str(path)).iter():
        for key, value in element.attrib.items():
            if key.endswith('href') and not value.startswith(
                ('data:', 'http:', 'https:', '#', 'file:')
            ):
                assert (path.parent / value).exists(), (path, value)
print('Inkscape retained resources checks passed')

cultures = {'cs', 'de', 'es', 'fr', 'it', 'ko', 'pl', 'pt-BR', 'ru', 'tr', 'zh-Hans', 'zh-Hant'}
satellites = list(Path('/usr/lib64/dotnet').rglob('*.resources.dll'))
assert any(path.parent.name == 'ja' for path in satellites)
assert not any(path.parent.name in cultures for path in satellites)
for path in Path('/usr/local/lib/node_modules').rglob('*'):
    assert not path.name.endswith(('.js.map', '.mjs.map', '.css.map')), path
print('Removed satellites and source maps checks passed')
PY

for language in en ja; do
    locale -a | grep -i "${language}_" > /dev/null
    mkdir -p "$COMPACTION_TEST_DIR/mkdocs-$language/docs"
    cat > "$COMPACTION_TEST_DIR/mkdocs-$language/mkdocs.yml" <<EOF
site_name: 日本語 English
site_url: https://example.invalid/
theme:
  name: material
  language: $language
plugins:
  - search:
      lang: [$language]
  - awesome-nav
markdown_extensions:
  - callouts
  - pymdownx.superfences
EOF
    printf '# 日本語 English\n\n検索の確認。\n\n> [!NOTE]\n> Retained resources\n' \
        > "$COMPACTION_TEST_DIR/mkdocs-$language/docs/index.md"
    mkdocs build --strict -q -f "$COMPACTION_TEST_DIR/mkdocs-$language/mkdocs.yml"
    test -s "$COMPACTION_TEST_DIR/mkdocs-$language/site/search/search_index.json"
    DOTNET_CLI_UI_LANGUAGE=$language dotnet --info > "$COMPACTION_TEST_DIR/dotnet-$language.txt"
done

for language in 'C#' VB; do
    directory="$COMPACTION_TEST_DIR/dotnet-${language//#/sharp}"
    mkdir -p "$directory"
    (
        cd "$directory"
        dotnet new console -lang "$language" --no-restore
        dotnet restore --ignore-failed-sources
        DOTNET_CLI_UI_LANGUAGE=ja dotnet build --no-restore
        dotnet run --no-build | grep -E 'Hello.*World!'
    )
done

pwsh -NoProfile -Command '
    foreach ($culture in "en-US", "ja-JP") {
        [System.Threading.Thread]::CurrentThread.CurrentUICulture = [cultureinfo]$culture
        Get-Help Get-ChildItem | Out-Null
    }
    Write-Output "PowerShell culture checks passed"
'
node - <<'JS'
const zod = require('/usr/local/lib/node_modules/textlint/node_modules/zod');
if (!zod.string().safeParse('English 日本語').success) throw new Error('Zod validation failed');
const sre = require('/usr/local/lib/node_modules/@marp-team/marp-cli/node_modules/speech-rule-engine');
sre.setupEngine({locale: 'en'});
sre.engineReady().then(() => {
  const result = sre.toSpeech('<math xmlns="http://www.w3.org/1998/Math/MathML"><mn>1</mn><mo>+</mo><mn>2</mn></math>');
  if (!result) throw new Error('English math speech failed');
  console.log('Zod and English math speech checks passed:', result);
}).catch(error => { console.error(error); process.exitCode = 1; });
JS

python -B - <<'PY'
import io
from markitdown import MarkItDown
from watchdog.observers import Observer
result = MarkItDown().convert_stream(
    io.BytesIO('<html><body><h1>日本語 English</h1></body></html>'.encode()),
    file_extension='.html',
)
assert '日本語 English' in result.markdown
print('MarkItDown and watchdog checks passed')
PY
if readelf --sections /usr/local/bin/git | grep -E '[[:space:]]\.debug_' > /dev/null; then
    echo 'Git debug sections remain' >&2
    exit 1
fi
for alias in git git-add git-clone; do
    test "$(stat -Lc%i /usr/local/bin/git)" = "$(stat -Lc%i "/usr/local/libexec/git-core/$alias")"
done
echo 'Image compaction integration checks passed'
