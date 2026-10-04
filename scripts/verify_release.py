"""Install the published package into a new consumer, build and run examples.

Uses the registry dependency rather than a local path override. The temporary
consumer lives under _build/verification and is preserved for inspection.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--moon', default='moon')
    parser.add_argument('--version', default='0.1.1')
    options = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', options.version):
        raise SystemExit('Version must be a concrete X.Y.Z release')
    parent = ROOT / '_build/verification'
    parent.mkdir(parents=True, exist_ok=True)
    consumer = Path(tempfile.mkdtemp(prefix='consumer-', dir=parent))
    (consumer / 'moon.mod').write_text(
        'name = "verification/mooncoap_consumer"\n'
        'version = "0.0.0"\npreferred_target = "native"\n'
        'import {\n  "moonbitlang/async@0.22.4",\n}\n', encoding='utf-8')
    for source, package in [('basic', 'cmd/main'), ('udp_loopback', 'cmd/network')]:
        directory = consumer / package
        directory.mkdir(parents=True)
        (directory / 'main.mbt').write_text((ROOT / f'examples/{source}/main.mbt').read_text(encoding='utf-8'), encoding='utf-8')
        (directory / 'moon.pkg').write_text((ROOT / f'examples/{source}/moon.pkg').read_text(encoding='utf-8'), encoding='utf-8')
    def moon(*arguments):
        print('RUN', ' '.join([options.moon, *arguments]), flush=True)
        subprocess.run([options.moon, *arguments], cwd=consumer, check=True)
    moon('update')
    moon('add', f'sujy123456/mooncoap@{options.version}')
    moon('fmt')
    for target in ['js', 'native']:
        moon('check', '--target', target, '--deny-warn')
        moon('build', '--target', target, '--deny-warn')
        moon('run', 'cmd/main', '--target', target, '--deny-warn')
    moon('run', 'cmd/network', '--target', 'native', '--deny-warn')
    installed = consumer / '.mooncakes/sujy123456/mooncoap/moon.mod'
    metadata = installed.read_text(encoding='utf-8')
    actual = re.search(r'^version\s*=\s*"([^"]+)"', metadata, re.MULTILINE)
    assert actual and actual.group(1) == options.version, 'Installed release version mismatch'
    assert 'path =' not in (consumer / 'moon.mod').read_text(encoding='utf-8'), 'Local path dependency detected'
    print(f'Published {options.version} registry installation verified: {consumer}', flush=True)


if __name__ == '__main__':
    main()
