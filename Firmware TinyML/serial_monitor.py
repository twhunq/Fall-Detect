"""Interactive serial monitor (also accepts collection labels)."""
import argparse
import subprocess
import sys
from flash import find_cli, select_port


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port')
    parser.add_argument('--cli')
    args = parser.parse_args()
    cli = find_cli(args.cli)
    port = select_port(cli, args.port)
    print('Serial', port, '115200 baud; Ctrl+C de thoat. Thu thap: go nhan + Enter.', flush=True)
    subprocess.run([cli, 'monitor', '--port', port, '--config', 'baudrate=115200'], check=True)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print('[LOI]', error, file=sys.stderr)
        sys.exit(1)
