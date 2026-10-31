"""Sinh am bao dong cho app (chi dung stdlib).

Chay: python mobile/tools/make_alarm_sound.py
Tao: assets/sounds/alarm.wav, assets/sounds/silence.wav va ban sao
android/app/src/main/res/raw/alarm.wav (am kenh thong bao Android).
"""
import math
import shutil
import struct
import wave
from pathlib import Path

RATE = 22050
ROOT = Path(__file__).resolve().parent.parent


def write_wav(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", s) for s in samples))


def siren(duration=2.0, seg=0.25, f1=880.0, f2=1320.0, fade=0.01, amp=0.85):
    n = int(RATE * duration)
    seg_n = int(RATE * seg)
    fade_n = int(RATE * fade)
    out = []
    phase = 0.0
    for i in range(n):
        f = f1 if (i // seg_n) % 2 == 0 else f2
        phase += 2 * math.pi * f / RATE
        pos = i % seg_n
        env = min(1.0, pos / fade_n, (seg_n - 1 - pos) / fade_n)  # fade moi doan
        out.append(int(32767 * amp * env * math.sin(phase)))
    return out


def main():
    sounds = ROOT / "assets" / "sounds"
    write_wav(sounds / "alarm.wav", siren())
    write_wav(sounds / "silence.wav", [0] * RATE)
    raw = ROOT / "android" / "app" / "src" / "main" / "res" / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(sounds / "alarm.wav", raw / "alarm.wav")
    print("OK:", sounds)


if __name__ == "__main__":
    main()
