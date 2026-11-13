#!/usr/bin/env python3
"""Docker Hub の description 用 README を生成する。

Docker Hub の full description は 25,000 バイトが上限で、超過分は途中で切り捨てられる。
README のうちリポジトリの保守者向けの部分を除外マーカーで外し、末尾に GitHub の README への
リンクを付ける。それでも上限を超える場合は、末尾の `## ` 節を丸ごと外して警告を出す。

除外マーカー (GitHub 上では表示されない HTML コメント):
    <!-- dockerhub:exclude:start -->
    ...
    <!-- dockerhub:exclude:end -->

使い方: make-dockerhub-readme.py <入力 README> <出力ファイル> <GitHub の README の URL>
"""

import re
import sys

LIMIT_BYTES = 25000
START = "<!-- dockerhub:exclude:start -->"
END = "<!-- dockerhub:exclude:end -->"


def strip_excluded(text: str) -> str:
    out = []
    excluding = False
    for line in text.splitlines(keepends=True):
        marker = line.strip()
        if marker == START:
            if excluding:
                sys.exit(f"error: nested {START}")
            excluding = True
            continue
        if marker == END:
            if not excluding:
                sys.exit(f"error: {END} without {START}")
            excluding = False
            continue
        if not excluding:
            out.append(line)
    if excluding:
        sys.exit(f"error: {START} without {END}")
    # 除外で生じた連続空行を 1 行にまとめる
    return re.sub(r"\n{3,}", "\n\n", "".join(out))


def split_sections(text: str) -> list[str]:
    """コードブロック外の `## ` 見出しで分割する。先頭要素は最初の見出しより前の部分。"""
    sections = [[]]
    fenced = False
    for line in text.splitlines(keepends=True):
        if line.startswith("```"):
            fenced = not fenced
        if not fenced and line.startswith("## "):
            sections.append([])
        sections[-1].append(line)
    return ["".join(s) for s in sections]


def size(text: str) -> int:
    return len(text.encode("utf-8"))


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    src, dest, full_readme_url = sys.argv[1:]
    with open(src, encoding="utf-8") as f:
        body = strip_excluded(f.read()).rstrip("\n") + "\n"
    footer = f"\n---\n\nすべての内容は [GitHub の README]({full_readme_url}) を参照してください。\n"

    sections = split_sections(body)
    dropped = []
    while size("".join(sections) + footer) > LIMIT_BYTES and len(sections) > 1:
        dropped.insert(0, sections.pop().splitlines()[0])
    result = "".join(sections).rstrip("\n") + "\n" + footer
    if size(result) > LIMIT_BYTES:
        sys.exit(f"error: README for Docker Hub is {size(result)} bytes even after dropping all sections")
    if dropped:
        print(
            f"::warning::README for Docker Hub exceeds {LIMIT_BYTES} bytes; dropped trailing sections: "
            + ", ".join(dropped)
            + ". Mark maintainer-only parts with dockerhub:exclude markers."
        )

    with open(dest, "w", encoding="utf-8") as f:
        f.write(result)
    print(f"README for Docker Hub: {size(result)} / {LIMIT_BYTES} bytes")


if __name__ == "__main__":
    main()
