"""Check a teacher deployment checkout against the canonical Pages generator."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def files(root):
    return {path.relative_to(root): path for path in root.rglob('*') if path.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mirror', type=Path, help='Teacher deployment checkout or candidate')
    args = parser.parse_args()
    mirror = args.mirror.resolve()
    with tempfile.TemporaryDirectory() as folder:
        generated = Path(folder)
        subprocess.run([sys.executable, str(ROOT / 'scripts/prepare-pages.py'),
                        'teacher', str(generated), '--enable-quiz-manager'], check=True)
        expected = files(generated)
        actual = {Path('index.html'): mirror / 'index.html'}
        for tree in ('teacher', 'shared'):
            actual.update({Path(tree) / name: path for name, path in files(mirror / tree).items()})
        for name in sorted(expected.keys() ^ actual.keys()):
            print(f'Unexpected or missing deployment file: {name}', file=sys.stderr)
        mismatched = [name for name in sorted(expected.keys() & actual.keys())
                      if not actual[name].is_file()
                      or actual[name].read_bytes() != expected[name].read_bytes()]
        for name in mismatched:
            print(f'Deployment bytes differ: {name}', file=sys.stderr)
        if mismatched or expected.keys() != actual.keys():
            return 1
    print('PASS: teacher deployment files byte-match the canonical generator')
    return 0


if __name__ == '__main__':
    sys.exit(main())
