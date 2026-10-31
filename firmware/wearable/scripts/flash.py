"""Build current sources for ESP32-S3; never flash the old ESP32 binaries."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

SCRIPTS_DIR = Path(__file__).resolve().parent
ROOT = SCRIPTS_DIR.parent
REPO_ROOT = ROOT.parents[1]
CORE_VERSION = '3.3.12'
MIN_CORE_VERSION = (3, 3, 8)
FQBN = ('esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,PSRAM=enabled,'
        'FlashSize=4M,FlashMode=dio,PartitionScheme=min_spiffs,CPUFreq=80')
INDEX = 'https://espressif.github.io/arduino-esp32/package_esp32_index.json'


def parse_version(text):
    try:
        return tuple(int(part) for part in str(text).split('.')[:3])
    except ValueError:
        return ()


def find_supported_core(platforms):
    for p in platforms:
        if p.get('id') != 'esp32:esp32':
            continue
        ver = p.get('installed_version', '')
        parsed = parse_version(ver)
        if len(parsed) == 3 and parsed[0] == 3 and parsed >= MIN_CORE_VERSION:
            return ver
    return None


def find_cli(explicit=None):
    candidates = [explicit, os.environ.get('ARDUINO_CLI'), shutil.which('arduino-cli'),
                  REPO_ROOT / '.tools/arduino-cli/arduino-cli.exe',
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


def find_esptool_and_boot_app0(active_core):
    base = Path(os.environ.get('LOCALAPPDATA', '')) / 'Arduino15' / 'packages' / 'esp32'
    esptools = sorted((base / 'tools' / 'esptool_py').glob('*/esptool.exe'), reverse=True)
    boot_app0 = base / 'hardware' / 'esp32' / active_core / 'tools' / 'partitions' / 'boot_app0.bin'
    if esptools and boot_app0.is_file():
        return str(esptools[0]), str(boot_app0)
    return None, None


def is_windows_usb_jtag(port):
    if os.name != 'nt':
        return False
    try:
        from serial.tools import list_ports
        for info in list_ports.comports():
            if info.device.upper() == str(port).upper():
                return info.vid == 0x303A and info.pid == 0x1001
    except Exception:
        return False
    return False


def resolve_post_reset_port(port):
    try:
        from serial.tools import list_ports
        ports = list(list_ports.comports())
        if any(p.device.upper() == str(port).upper() for p in ports):
            return port
        espressif = [p.device for p in ports if p.vid == 0x303A]
        if len(espressif) == 1:
            return espressif[0]
    except Exception:
        pass
    return port


def usb_jtag_reset_and_upload(port, output, sketch_name, active_core):
    """Windows usbser.sys workaround: close COM handle across USB-JTAG reset, then flash at 460800 with no-reset."""
    import serial
    esptool, boot_app0 = find_esptool_and_boot_app0(active_core)
    if not esptool:
        raise RuntimeError('Khong tim thay esptool.exe / boot_app0.bin de nap ESP32-S3.')
    print(f'[USB-JTAG] Reset {port} vao che do nap ROM va mo lai handle moi...', flush=True)
    s = serial.Serial(port, 115200, timeout=0.5, write_timeout=0.5, dsrdtr=False, rtscts=False)
    try:
        s.rts = False
        s.dtr = False
        time.sleep(0.1)
        s.dtr = True
        s.rts = False
        time.sleep(0.1)
        s.rts = True
        s.dtr = False
        s.rts = True
        time.sleep(0.1)
        s.dtr = False
        s.rts = False
    except OSError:
        # USB-Serial/JTAG may re-enumerate immediately on the final RTS edge.
        pass
    finally:
        s.close()
    time.sleep(1.5)
    port = resolve_post_reset_port(port)
    cmd = [
        esptool, '--chip', 'esp32s3', '--port', port, '--baud', '460800',
        '--before', 'no-reset', '--after', 'hard-reset',
        'write-flash', '-z', '--flash-mode', 'keep', '--flash-freq', 'keep', '--flash-size', 'keep',
        '0x0', str(output / f'{sketch_name}.ino.bootloader.bin'),
        '0x8000', str(output / f'{sketch_name}.ino.partitions.bin'),
        '0xe000', boot_app0,
        '0x10000', str(output / f'{sketch_name}.ino.bin'),
    ]
    print('[RUN]', subprocess.list2cmdline(cmd), flush=True)
    subprocess.run(cmd, check=True)


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
    active_core = find_supported_core(platforms)
    if not active_core:
        raise RuntimeError('Can core esp32 >= 3.3.8 (3.3.x); chay lai voi --install-core.')
    sketch = ROOT / 'src' / args.sketch
    output = ROOT / 'build' / 'esp32s3' / args.sketch
    output.mkdir(parents=True, exist_ok=True)
    # Compile must succeed in this invocation before any upload is attempted.
    run(cli, 'compile', '--fqbn', FQBN, '--warnings', 'all',
        '--output-dir', output, sketch)
    (output / 'build_target.json').write_text(json.dumps(
        {'fqbn': FQBN, 'core': active_core, 'sketch': args.sketch}, indent=2), encoding='utf-8')
    if args.build_only:
        print('[OK] Build ESP32-S3:', output)
        return
    port = select_port(cli, args.port)
    if is_windows_usb_jtag(port) and find_esptool_and_boot_app0(active_core)[0]:
        usb_jtag_reset_and_upload(port, output, args.sketch, active_core)
    else:
        try:
            run(cli, 'upload', '--fqbn', FQBN, '--port', port, '--input-dir', output, sketch)
        except subprocess.CalledProcessError:
            if os.name != 'nt':
                raise
            usb_jtag_reset_and_upload(port, output, args.sketch, active_core)
    print('[OK] Da nap ESP32-S3. Mo Serial 115200; cong COM co the thay doi sau reset.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError, ValueError) as error:
        print('[LOI]', error, file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
