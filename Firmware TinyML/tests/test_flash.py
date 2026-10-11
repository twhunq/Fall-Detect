import io
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import flash


class FlashTests(unittest.TestCase):
    def test_unknown_com1_is_not_silently_selected(self):
        listing = {'detected_ports': [{'port': {'address': 'COM1', 'protocol': 'serial'}}]}
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(listing))
        with patch.object(flash, 'run', return_value=result), patch('sys.stdin.isatty', return_value=False):
            with self.assertRaises(RuntimeError):
                flash.select_port('cli')

    def test_single_espressif_port_selected_beside_unknown_port(self):
        listing = {'detected_ports': [
            {'port': {'address': 'COM1', 'protocol': 'serial', 'properties': {}}},
            {'port': {'address': 'COM3', 'protocol': 'serial', 'properties': {'vid': '0x303A'}}}]}
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(listing))
        with patch.object(flash, 'run', return_value=result), patch('sys.stdout', io.StringIO()):
            self.assertEqual(flash.select_port('cli'), 'COM3')

    def test_two_espressif_ports_are_not_guessed(self):
        listing = {'detected_ports': [
            {'port': {'address': p, 'protocol': 'serial', 'properties': {'vid': '0x303a'}}}
            for p in ('COM3', 'COM5')]}
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(listing))
        with patch.object(flash, 'run', return_value=result), patch('sys.stdin.isatty', return_value=False), \
                patch('sys.stdout', io.StringIO()):
            with self.assertRaises(RuntimeError):
                flash.select_port('cli')

    def test_failed_build_cannot_upload_stale_binary(self):
        installed = subprocess.CompletedProcess([], 0, stdout=json.dumps({'platforms': [
            {'id': 'esp32:esp32', 'installed_version': flash.CORE_VERSION}]}))
        with patch.object(flash, 'find_cli', return_value='cli'), \
                patch.object(flash, 'run', side_effect=[installed, subprocess.CalledProcessError(1, 'compile')]) as run, \
                patch.object(flash, 'select_port') as select, patch('sys.argv', ['flash.py', '--port', 'COM9']):
            with self.assertRaises(subprocess.CalledProcessError):
                flash.main()
            self.assertEqual(run.call_count, 2)
            select.assert_not_called()

    def test_collection_driver_and_config_match_detection(self):
        base = flash.ROOT / 'esp32'
        for name in ('mpu6050_i2c.h', 'board_config.h'):
            self.assertEqual((base / 'fall_detection_esp32' / name).read_bytes(),
                             (base / 'data_collection' / name).read_bytes())


if __name__ == '__main__':
    unittest.main()
