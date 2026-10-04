"""Count authored code lines; generated interfaces and dependencies are excluded.

One line counts once if it contains lexical content outside comments. This is
not a complexity metric. Strings (including escaped comment delimiters) remain
code. MoonBit // comments and nested /* */ comments are stripped lexically.
"""
import argparse
import json
from pathlib import Path

EXCLUDE = {'.git', '.mooncakes', '_build', 'dist', '.venv', '__pycache__',
           'test-results', '.repos', '.githooks'}


def code_lines(text):
    block = 0
    quote = None
    escaped = False
    counted = 0
    for line in text.splitlines():
        # MoonBit raw string continuation is literal source, not a comment.
        if block == 0 and quote is None and line.lstrip().startswith('#|'):
            counted += 1
            continue
        visible = False
        i = 0
        while i < len(line):
            char = line[i]
            pair = line[i:i + 2]
            if block:
                if pair == '/*':
                    block += 1
                    i += 2
                elif pair == '*/':
                    block -= 1
                    i += 2
                else:
                    i += 1
                continue
            if quote:
                visible = True
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == quote:
                    quote = None
                i += 1
                continue
            if pair == '//':
                break
            if pair == '/*':
                block += 1
                i += 2
                continue
            if char in {'"', "'"}:
                quote = char
                visible = True
            elif not char.isspace():
                visible = True
            i += 1
        if visible:
            counted += 1
        # A character/string literal cannot span source lines except raw lines.
        quote = None
        escaped = False
    return counted


def report(root):
    totals = dict(implementation=0, tests=0, examples=0, documentation=0,
                  other_languages=0)
    modules = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if not path.is_file() or any(part in EXCLUDE for part in relative.parts):
            continue
        if path.name.endswith('.mbti'):
            continue
        if path.suffix == '.mbt':
            if path.name.endswith(('_test.mbt', '_wbtest.mbt')):
                kind = 'tests'
            elif relative.parts[0] in {'examples', 'cmd'}:
                kind = 'examples'
            else:
                kind = 'implementation'
            lines = code_lines(path.read_text(encoding='utf-8'))
        elif path.suffix.lower() in {'.md', '.txt'} or path.name == 'LICENSE':
            kind = 'documentation'
            lines = len(path.read_text(encoding='utf-8').splitlines())
        elif path.suffix.lower() in {'.py', '.js', '.c', '.h', '.ps1', '.sh'}:
            kind = 'other_languages'
            lines = sum(bool(line.strip()) for line in path.read_text(encoding='utf-8').splitlines())
        else:
            continue
        totals[kind] += lines
        modules[relative.as_posix()] = dict(category=kind, lines=lines)
    return dict(method='nonblank authored lexical MoonBit lines excluding comments',
                totals=totals, files=modules)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--minimum', type=int, default=4001)
    parser.add_argument('--json', action='store_true')
    options = parser.parse_args()
    result = report(options.root.resolve())
    if options.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for kind, count in result['totals'].items():
            print(f'{kind}: {count}')
        for name, entry in result['files'].items():
            if entry['category'] == 'implementation':
                print(f"  {name}: {entry['lines']}")
    if result['totals']['implementation'] < options.minimum:
        raise SystemExit(f"Implementation below required minimum {options.minimum}")


if __name__ == '__main__':
    main()
