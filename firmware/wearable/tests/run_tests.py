"""Host tests; requires NumPy and g++/clang++ or Zig (no PCB required)."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parents[1]
BUNDLED_ZIG = REPO_ROOT / '.tools/zig-windows-x86_64-0.13.0/zig.exe'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cxx', help='Path to g++, clang++ or zig executable')
args = parser.parse_args()
compiler = (args.cxx or shutil.which('g++') or shutil.which('clang++') or shutil.which('zig') or
            (str(BUNDLED_ZIG) if BUNDLED_ZIG.is_file() else None))
if not compiler:
    parser.error('Specify --cxx PATH_TO_COMPILER')
command = [compiler]
if Path(compiler).stem == 'zig':
    command.append('c++')
out = ROOT / 'build' / 'tests'
out.mkdir(parents=True, exist_ok=True)
subprocess.run([sys.executable, str(ROOT / 'tests/test_flash.py')], check=True)
fixture = out / 'model-fixture.bin'
subprocess.run([sys.executable, str(ROOT / 'tests/make_model_fixture.py'), str(fixture)], check=True)
for name in ('runtime_test', 'driver_test', 'detection_test', 'notify_test', 'cloud_test',
             'inactivity_test', 'lan_alert_test'):
    binary = out / (name + ('.exe' if sys.platform == 'win32' else ''))
    subprocess.run(command + ['-std=c++17', '-O2', '-Wall', '-Wextra', '-Werror',
                             '-I' + str(ROOT / 'tests/stubs'),
                             '-I' + str(ROOT / 'src/fall_detection_esp32'),
                             str(ROOT / 'tests' / (name + '.cpp')), '-o', str(binary)], check=True)
    subprocess.run([str(binary)] + ([str(fixture)] if name == 'runtime_test' else []), check=True)
