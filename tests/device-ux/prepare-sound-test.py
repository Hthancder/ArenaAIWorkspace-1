import pathlib
import subprocess
import sys
import tempfile
import wave

script = pathlib.Path(__file__).resolve().parents[2] / 'tools/prepare-ui-sound.py'
with tempfile.TemporaryDirectory() as tmp:
    a, b = pathlib.Path(tmp) / 'in.wav', pathlib.Path(tmp) / 'out.wav'
    with wave.open(str(a), 'wb') as wav:
        wav.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
        wav.writeframes(b'\x00\x00' * 20000)
    def run(*args):
        return subprocess.run([sys.executable, str(script), *args], capture_output=True)
    assert run('select', str(a), str(b)).returncode != 0
    assert run('select', str(a), str(b), '--trim').returncode == 0
    assert b.stat().st_size == 44 + 24000
    with wave.open(str(b), 'rb') as wav:
        assert (wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.getnframes()) == (48000, 1, 2, 12000)
print('UI sound conversion regression tests passed')
