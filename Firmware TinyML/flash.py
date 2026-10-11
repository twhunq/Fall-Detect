"""Build current sources for ESP32-S3; never flash the old ESP32 binaries."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
CORE_VERSION = '3.3.8'
FQBN = ('esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,PSRAM=enabled,'
        'FlashSize=4M,FlashMode=dio,PartitionScheme=min_spiffs,CPUFreq=80')
INDEX = 'https://espressif.github.io/arduino-esp32/package_esp32_index.json'


def find_cli(explicit=None):
    candidates = [explicit, os.environ.get('ARDUINO_CLI'), shutil.which('arduino-cli'),
                  ROOT.parent / '.tools/arduino-cli/arduino-cli.exe',
                  Path(os.environ.get('LOCALAPPDATA', '')) /
                  'Programs/Arduino IDE/resources/app/lib/backend/resources/arduino-cli.exe',
                  Path(os.environ.get('ProgramFiles', 'C:/Program Files')) /
                  'Arduino IDE/resources/app/lib/backend/resources/arduino-cli.exe']
    for path in candidates:
        if path and Path(path).is_file():
            return str(path)
    raise RuntimeError('Khong tim thay arduino-cli. Cai Arduino CLI hoac truyen --cli DUONG_DAN.')


def run(cli, *args, capture=False):
    cmd = [cli, *map(str, args)]
    if not capture:
        print('[RUN]', subprocess.list2cmdline(cmd), flush=True)
    return subprocess.run(cmd, check=True, text=True, encoding='utf-8',
                          errors='replace', capture_output=capture)


def select_port(cli, explicit=None):
    if explicit:
        return explicit
    info = json.loads(run(cli, 'board', 'list', '--format', 'json', capture=True).stdout)
    ports = [p['port'] for p in info.get('detected_ports', [])
             if p.get('port', {}).get('protocol') == 'serial']
    if not ports:
        raise RuntimeError('Khong co cong serial. Cam USB-C; neu can giu BOOT, bam RESET, tha BOOT.')
    known = [p for p in ports if str(p.get('properties', {}).get('vid', '')).lower()
             in ('0x303a', '303a')]
    # Exactly one Espressif USB device: unambiguous even beside unrelated ports (e.g. COM1).
    if len(known) == 1:
        print('[PORT] Tu chon ESP32-S3:', known[0]['address'], flush=True)
        return known[0]['address']
    print('Can chon cong ESP32-S3 (khong tu chon cong serial khong ro thiet bi):')
    for p in ports:
        print(' ', p['address'], p.get('label', ''))
    if not sys.stdin.isatty():
        raise RuntimeError('Can chi dinh --port COMx neu khong nhan dien duoc duy nhat mot ESP32 USB.')
    selected = input('Nhap cong COM: ').strip()
    if selected not in [p['address'] for p in ports]:
        raise RuntimeError('Cong da chon khong nam trong danh sach.')
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--sketch', choices=['fall_detection_esp32', 'data_collection'],
                        default='fall_detection_esp32')
    parser.add_argument('--port', help='Vi du COM3; khong tu chon cong dau tien neu co nhieu cong')
    parser.add_argument('--cli', help='Duong dan arduino-cli.exe')
    parser.add_argument('--install-core', action='store_true', help='Cai core ESP32 da kiem thu')
    args = parser.parse_args()
    cli = find_cli(args.cli)
    if args.install_core:
        run(cli, 'core', 'update-index', '--additional-urls', INDEX)
        run(cli, 'core', 'install', 'esp32:esp32@' + CORE_VERSION, '--additional-urls', INDEX)
    installed = json.loads(run(cli, 'core', 'list', '--format', 'json', capture=True).stdout)
    platforms = installed.get('platforms', []) if isinstance(installed, dict) else installed
    if not any(p.get('id') == 'esp32:esp32' and
               p.get('installed_version') == CORE_VERSION for p in platforms):
        raise RuntimeError('Can core esp32 ' + CORE_VERSION + '; chay lai voi --install-core.')
    sketch = ROOT / 'esp32' / args.sketch
    output = ROOT / 'build' / 'esp32s3' / args.sketch
    output.mkdir(parents=True, exist_ok=True)
    # Compile must succeed in this invocation before any upload is attempted.
    run(cli, 'compile', '--fqbn', FQBN, '--warnings', 'all',
        '--output-dir', output, sketch)
    (output / 'build_target.json').write_text(json.dumps(
        {'fqbn': FQBN, 'core': CORE_VERSION, 'sketch': args.sketch}, indent=2), encoding='utf-8')
    if args.build_only:
        print('[OK] Build ESP32-S3:', output)
        return
    port = select_port(cli, args.port)
    run(cli, 'upload', '--fqbn', FQBN, '--port', port, '--input-dir', output, sketch)
    print('[OK] Da nap ESP32-S3. Mo Serial 115200; cong COM co the thay doi sau reset.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError, ValueError) as error:
        print('[LOI]', error, file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
