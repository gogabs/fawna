# Passos no chão de terra batida/argila firme do abrigo (abrigo/passo_1..5.ogg), gerados por código.
# Uso: python tools/sons_abrigo.py (precisa de numpy, scipy, soundfile e ffmpeg).
import numpy as np, soundfile as sf, subprocess, os, tempfile
from scipy.signal import butter, sosfilt
SR = 48000
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds', 'abrigo'); os.makedirs(OUT, exist_ok=True)

def filt(x, kind, f, o=2): return sosfilt(butter(o, f, kind, fs=SR, output='sos'), x)

def passo(seed):
    rng = np.random.default_rng(seed)
    n = int(0.26 * SR); t = np.arange(n) / SR; y = np.zeros(n)
    # corpo: batida surda no chão firme (grave curto, com leve queda de altura)
    # (ruído de baixa frequência com passa-baixa agressivo, sem altura definida: baque e não nota)
    thud = filt(rng.standard_normal(n), 'lp', rng.uniform(110, 150), 4) * np.exp(-t / 0.04)
    y += thud / np.max(np.abs(thud)) * 0.5
    # superfície: terra compactada, ruído médio e curto
    body = filt(rng.standard_normal(n), 'bp', [250, 1400]) * np.exp(-t / 0.03)
    y += body * rng.uniform(0.7, 1.0)
    # grãos: poucos estalinhos secos de cascalho/argila, logo depois do contato
    for _ in range(rng.integers(3, 7)):
        i = int(rng.uniform(0.004, 0.09) * SR); m = rng.integers(25, 90)
        g = filt(rng.standard_normal(m), 'bp', [rng.uniform(1800, 3200), rng.uniform(4500, 7000)]) * np.linspace(1, 0, m) ** 2
        y[i:i + m] += g * rng.uniform(0.15, 0.45)
    # arrasto do calcanhar, bem baixo
    s0 = int(0.05 * SR); s = filt(rng.standard_normal(n - s0), 'bp', [600, 2600]) * np.exp(-np.arange(n - s0) / SR / 0.05)
    y[s0:] += s * 0.12
    y *= np.minimum(1, t / 0.002)
    y = filt(y, 'lp', 6500, 1)
    return y / np.max(np.abs(y)) * 0.35  # bem baixo (~ -6 dB do anterior)

for i in range(1, 6):
    tmp = tempfile.mktemp(suffix='.wav'); sf.write(tmp, passo(900 + i), SR)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '5', os.path.join(OUT, f'passo_{i}.ogg')], check=True)
    os.remove(tmp)
print('ok')
