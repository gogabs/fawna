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


# --- Porta (abrigo/porta_abre_N.ogg, porta_fecha_N.ogg): porta improvisada de bambu e couro,
# rangido de madeira seca + arrasto + batida surda no fim.
def rangido(rng, dur, f0, f1):
    n = int(dur * SR); t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** (t / dur) * (1 + 0.03 * np.sin(2 * np.pi * rng.uniform(5, 9) * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    # pulsos de atrito (stick-slip): serra com trepidação irregular
    saw = ((ph / (2 * np.pi)) % 1.0) * 2 - 1
    saw *= 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rng.uniform(28, 46) * t + rng.uniform(0, 6)))
    y = filt(saw, 'bp', [350, 2200])
    env = np.minimum(1, t / 0.05) * np.minimum(1, (dur - t) / 0.12) * (0.6 + 0.4 * filt(rng.standard_normal(n), 'lp', 9, 1) / 0.3).clip(0.2, 1)
    return y * env

def porta(seed, abre):
    rng = np.random.default_rng(seed)
    dur = rng.uniform(0.55, 0.75) if abre else rng.uniform(0.4, 0.55)
    tail = 0.25; n = int((dur + tail) * SR); y = np.zeros(n)
    f0, f1 = (rng.uniform(170, 210), rng.uniform(260, 340)) if abre else (rng.uniform(290, 340), rng.uniform(170, 210))
    c = rangido(rng, dur, f0, f1); y[:len(c)] += c * 0.55
    # arrasto no chão de terra
    sd = int(dur * SR); sc = filt(rng.standard_normal(sd), 'bp', [500, 2400]) * np.sin(np.pi * np.linspace(0, 1, sd)) ** 1.5
    y[:sd] += sc * 0.18
    # batida surda: no fechar forte (porta no batente); no abrir, leve encosto
    i = sd - int(0.02 * SR); m = int(0.16 * SR); tt = np.arange(m) / SR
    th = filt(rng.standard_normal(m), 'lp', rng.uniform(130, 170), 4) * np.exp(-tt / 0.045)
    th = th / np.max(np.abs(th)) * (0.9 if not abre else 0.35)
    tk = filt(rng.standard_normal(m), 'bp', [700, 3000]) * np.exp(-tt / 0.012) * (0.4 if not abre else 0.12)
    y[i:i + m] += th + tk
    y = filt(y, 'lp', 7000, 1)
    return y / np.max(np.abs(y)) * 0.5

for i in range(1, 4):
    for nome, abre in (('abre', True), ('fecha', False)):
        tmp = tempfile.mktemp(suffix='.wav'); sf.write(tmp, porta(500 + i + (0 if abre else 50), abre), SR)
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '5', os.path.join(OUT, f'porta_{nome}_{i}.ogg')], check=True)
        os.remove(tmp)
print('porta ok')
