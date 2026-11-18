#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Renames the app in a copy of the source tree, for a renamed copy packaged
by Tools/make-edition.sh. Only text people read changes: "Vorssaint" inside
Swift string literals, the usage descriptions in Info.plist and the localized
InfoPlist.strings. Identifiers, comments, keys such as VorssaintUpdatesDisabled
and the executable's name stay. Copyright and license notices keep the
original name, as the GPL asks of a modified copy.

    python3 Tools/rename-app.py SOURCE_COPY NAME
"""
import pathlib
import plistlib
import re
import sys

WORD = re.compile(r"(?<![A-Za-z0-9_])Vorssaint(?![A-Za-z0-9_])")
NOTICE = re.compile(r"©|copyright|license|licence|GPL|GNU", re.IGNORECASE)


def rename_text(text, name):
    """The text of one literal, renamed unless it is a legal notice."""
    if NOTICE.search(text):
        return text, 0
    return WORD.subn(name, text)


def rename_swift(source, name):
    """Renames inside string literals only, skipping comments and the code
    of interpolations. Handles plain, multi-line and raw (#"...") strings."""
    out, count, i, n = [], 0, 0, len(source)
    # A stack of open interpolations: the parentheses depth inside each.
    while i < n:
        if source.startswith("//", i):
            end = source.find("\n", i)
            end = n if end < 0 else end
            out.append(source[i:end]); i = end
            continue
        if source.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if source.startswith("/*", j): depth += 1; j += 2
                elif source.startswith("*/", j): depth -= 1; j += 2
                else: j += 1
            out.append(source[i:j]); i = j
            continue
        match = re.compile(r'(#*)("""|")').match(source, i)
        if match and (match.group(1) or source[i] == '"'):
            hashes, quote = match.group(1), match.group(2)
            start = match.end()
            out.append(source[i:start])
            i, renamed = scan_literal(source, start, hashes, quote, name, out)
            count += renamed
            continue
        out.append(source[i]); i += 1
    return "".join(out), count


def scan_literal(source, i, hashes, quote, name, out):
    """Copies one literal from just after its opening quote, renaming its
    text; returns where it ends and how many names changed."""
    n, count, text = len(source), 0, []
    closing = quote + hashes
    escape = "\\" + hashes

    def flush():
        nonlocal count
        renamed, changed = rename_text("".join(text), name)
        out.append(renamed); count += changed; text.clear()

    while i < n:
        if source.startswith(closing, i):
            flush(); out.append(closing)
            return i + len(closing), count
        if source.startswith(escape + "(", i):
            # Interpolated code: copied as code, its own strings renamed.
            flush()
            out.append(escape + "(")
            i += len(escape) + 1
            depth, start = 1, i
            code = []
            while i < n and depth:
                if source[i] == '"' or (source[i] == "#" and re.match(r'#+"', source[i:])):
                    sub = re.compile(r'(#*)("""|")').match(source, i)
                    code.append(source[i:sub.end()])
                    inner = []
                    i, renamed = scan_literal(source, sub.end(), sub.group(1), sub.group(2), name, inner)
                    code.append("".join(inner)); count += renamed
                    continue
                if source[i] == "(": depth += 1
                elif source[i] == ")": depth -= 1
                code.append(source[i]); i += 1
            out.append("".join(code))
            continue
        if source.startswith(escape, i):
            text.append(source[i:i + len(escape) + 1]); i += len(escape) + 1
            continue
        if quote == '"' and source[i] == "\n":
            break
        text.append(source[i]); i += 1
    flush()
    return i, count


def main():
    root, name = pathlib.Path(sys.argv[1]), sys.argv[2]
    total = 0
    for path in sorted(root.glob("Sources/**/*.swift")):
        source = path.read_text(encoding="utf-8")
        renamed, count = rename_swift(source, name)
        if count:
            path.write_text(renamed, encoding="utf-8")
            total += count
    plist_path = root / "Resources/Info.plist"
    with open(plist_path, "rb") as handle:
        info = plistlib.load(handle)
    for key, value in info.items():
        if key.endswith("UsageDescription") and isinstance(value, str):
            info[key], count = rename_text(value, name)
            total += count
    with open(plist_path, "wb") as handle:
        plistlib.dump(info, handle)
    for path in sorted(root.glob("Resources/*.lproj/InfoPlist.strings")):
        data = path.read_bytes()
        encoding = "utf-16" if data[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8"
        lines, changed = [], 0
        for line in data.decode(encoding).splitlines(keepends=True):
            renamed, count = rename_text(line, name)
            lines.append(renamed); changed += count
        if changed:
            path.write_bytes("".join(lines).encode(encoding))
            total += changed
    print(f"renamed {total} mentions to {name}")
    if total == 0:
        sys.exit("nothing was renamed: the source layout changed")


if __name__ == "__main__":
    main()
