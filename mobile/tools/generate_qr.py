"""Sinh ma QR ghep noi camera K230 cho app "Bao Nga IoT".

Ma QR dan tren vo may la URI:
    cbn://pair?id=CBC-XXYYZZ&key=<64 ky tu hex>
trong do key = HMAC-SHA256(MASTER_KEY, MAC 6 byte) - dung cong thuc
DeviceIdentity::_napKhoa() (firmware/camera-k230/include/device_identity.h),
va id = tien to + 3 byte cuoi MAC viet HEX hoa.

Lay MAC bang lenh WHOAMI qua Serial cua cau noi (in ra ID|CBC-..|AA:BB:..|2|1).

Vi du:
    python mobile/tools/generate_qr.py --mac A0:B1:C2:7A:3F:91 --master <64hex>
    set BAONGA_MASTER_KEY=<64hex> & python mobile/tools/generate_qr.py --mac ... --out qr
Anh PNG can goi `qrcode[pil]` (pip install "qrcode[pil]"); thieu goi thi chi in URI.
MASTER_KEY la bi mat: khong commit, khong dan vao tai lieu.
"""
import argparse
import hashlib
import hmac
import os
import re
import sys
from pathlib import Path


def parse_mac(text):
    digits = re.sub(r'[^0-9A-Fa-f]', '', text)
    if len(digits) != 12:
        raise ValueError('MAC phai co 6 byte, vi du A0:B1:C2:7A:3F:91')
    return bytes.fromhex(digits)


def parse_master(text):
    text = text.strip()
    if not re.fullmatch(r'[0-9A-Fa-f]{64}', text):
        raise ValueError('MASTER_KEY phai la 64 ky tu hex (32 byte)')
    return bytes.fromhex(text)


def device_key(master, mac):
    return hmac.new(master, mac, hashlib.sha256).digest()


def device_id(mac, prefix='CBC'):
    return '%s-%02X%02X%02X' % (prefix, mac[3], mac[4], mac[5])


def pairing_uri(master, mac, prefix='CBC'):
    return 'cbn://pair?id=%s&key=%s' % (device_id(mac, prefix), device_key(master, mac).hex())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--mac', action='append', required=True, help='MAC Wi-Fi STA cua cau noi (lap lai cho nhieu may)')
    parser.add_argument('--master', help='MASTER_KEY 64 hex (hoac bien moi truong BAONGA_MASTER_KEY)')
    parser.add_argument('--prefix', default='CBC', help='Tien to ma may (DEVICE_ID_PREFIX), mac dinh CBC')
    parser.add_argument('--out', help='Thu muc ghi anh PNG <ma_may>.png')
    args = parser.parse_args(argv)

    master_text = args.master or os.environ.get('BAONGA_MASTER_KEY')
    if not master_text:
        parser.error('Can --master hoac bien moi truong BAONGA_MASTER_KEY')
    try:
        master = parse_master(master_text)
        macs = [parse_mac(m) for m in args.mac]
    except ValueError as e:
        parser.error(str(e))

    try:
        import qrcode
    except ImportError:
        qrcode = None
        if args.out:
            print('[CANH BAO] Chua co goi qrcode: pip install "qrcode[pil]". Chi in URI.', file=sys.stderr)

    out = Path(args.out) if args.out else None
    if out:
        out.mkdir(parents=True, exist_ok=True)
    for mac in macs:
        uri = pairing_uri(master, mac, args.prefix)
        ident = device_id(mac, args.prefix)
        print('%s  %s' % (ident, uri))
        if qrcode and out:
            img = qrcode.make(uri, error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=4)
            path = out / (ident + '.png')
            img.save(path)
            print('  -> %s' % path)
        elif qrcode:
            qr = qrcode.QRCode(border=1)
            qr.add_data(uri)
            qr.print_ascii(invert=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
