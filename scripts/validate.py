"""Repeatable local/CI verification; a failed command stops the run."""
import argparse
from pathlib import Path
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--moon', default='moon')
    parser.add_argument('--interop', action='store_true')
    options = parser.parse_args()
    def moon(*arguments):
        command = [options.moon, *arguments]
        print('RUN', ' '.join(command), flush=True)
        subprocess.run(command, cwd=ROOT, check=True)
    moon('version', '--all')
    moon('update')
    moon('fmt', '--check')
    for target in ['js', 'native']:
        for task in ['check', 'test', 'build']:
            moon(task, '--target', target, '--deny-warn')
        for example in ['basic', 'loss', 'discovery_cache']:
            moon('run', f'examples/{example}', '--target', target, '--deny-warn')
    moon('run', 'examples/udp_loopback', '--target', 'native', '--deny-warn')
    subprocess.run([sys.executable, str(ROOT / 'scripts/count_lines.py')], cwd=ROOT, check=True)
    if options.interop:
        subprocess.run([sys.executable, str(ROOT / 'scripts/interop.py'), '--moon', options.moon], cwd=ROOT, check=True)
    moon('package', '--list')
    print('All requested checks passed.', flush=True)


if __name__ == '__main__':
    main()
