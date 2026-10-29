#!/usr/bin/env python3
"""Run production-source Lua suites and measure executable-line coverage with Lua 5.1.

The denominator comes from all nested prototypes in luac's listing, including files
never loaded by a mock. This is line coverage, not branch or client integration coverage.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile


def measure(lua, luac):
    sources = sorted([*Path('DragonUI').rglob('*.lua'), *Path('DragonUI_Options').rglob('*.lua')])
    executable = {}
    for source in sources:
        # The client permits a UTF-8 BOM; vanilla standalone Lua's parser does not.
        listing = subprocess.run([luac, '-l', '-p', '-'], input=source.read_bytes().removeprefix(b'\xef\xbb\xbf'), capture_output=True, check=True)
        executable[str(source)] = {int(n) for n in re.findall(rb'^\s*\d+\s+\[(\d+)\]', listing.stdout, re.MULTILINE) if int(n) > 0}
    hits = {}
    tests = sorted(Path('tools').glob('*_test.lua'))
    with tempfile.TemporaryDirectory(prefix='dragonui-coverage-') as directory:
        for i, test in enumerate(tests):
            receipt = Path(directory) / str(i)
            result = subprocess.run([lua, 'tools/coverage_trace.lua', str(test), str(receipt)], capture_output=True, text=True)
            if result.returncode:
                raise RuntimeError(f'{test} failed:\n{result.stdout}\n{result.stderr}')
            for row in receipt.read_text().splitlines():
                source, line = row.rsplit('\t', 1)
                hits.setdefault(source, set()).add(int(line))
    files = {source: {'covered': len(lines & hits.get(source, set())), 'executable': len(lines)} for source, lines in executable.items()}
    covered, total = sum(f['covered'] for f in files.values()), sum(f['executable'] for f in files.values())
    return {'method': 'Lua 5.1 line hook / luac executable source lines across all nested prototypes',
            'tests_passed': len(tests), 'covered_lines': covered, 'executable_lines': total,
            'line_percent': round(covered / total * 100, 2) if total else 0,
            'branch_coverage': 'unmeasured', 'files': files}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua', default='lua5.1')
    parser.add_argument('--luac', default='luac5.1')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = measure(args.lua, args.luac)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f"{report['tests_passed']} suites passed; {report['covered_lines']}/{report['executable_lines']} executable lines ({report['line_percent']}%); branches unmeasured")
