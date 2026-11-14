"""Gera a batida do Caminheiro (assets/sounds/caminheiro/batida.ogg).

Um coração ouvido de dentro: duas pancadas graves ("tum-tum") de um tambor
bem abafado, com passa-baixa forte (só o gravão) e um reverb curto e escuro.
Os efeitos são aplicados aqui, no arquivo; o jogo só toca o resultado.

    python3 tools/som_caminheiro.py

Precisa de: python3 com numpy, e ffmpeg.
"""

import os
import subprocess
import tempfile

import numpy as np

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(RAIZ, "assets", "sounds", "caminheiro")
RATE = 44100

CORTE_HZ = 110.0  # passa-baixa: só o grave
REVERB_SEGUNDOS = 1.1  # cauda do reverb
REVERB_MISTURA = 0.35  # quanto do reverb entra na mistura


def pancada(n, inicio, volume, rng):
    """Uma pancada de tambor abafado: um grave que cai de tom e a pele."""
    som = np.zeros(n)
    t = np.arange(n - inicio) / RATE
    freq = 48.0 + 45.0 * np.exp(-t * 30.0)
    fase = 2 * np.pi * np.cumsum(freq) / RATE
    corpo = np.sin(fase) * np.exp(-t * 11.0)
    ataque = np.minimum(t / 0.004, 1.0)
    pele = rng.uniform(-1, 1, len(t)) * np.exp(-t * 60.0) * 0.6
    som[inicio:] = (corpo + pele) * ataque * volume
    return som


def biquad_passa_baixa(x, corte, q=0.707):
    """Filtro passa-baixa de 2ª ordem (RBJ)."""
    w = 2 * np.pi * corte / RATE
    alfa = np.sin(w) / (2 * q)
    c = np.cos(w)
    b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    a0, a1, a2 = 1 + alfa, -2 * c, 1 - alfa
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x):
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def passa_baixa(x, corte, ordens=2):
    """Passa-baixa íngreme: biquads em série (24 dB/oitava com 2)."""
    for _ in range(ordens):
        x = biquad_passa_baixa(x, corte)
    return x


def reverb(x, segundos, rng):
    """Reverb por convolução com uma resposta sintética: ruído que decai,
    escurecido (como uma sala de dentro do peito)."""
    n = int(RATE * segundos)
    t = np.arange(n) / RATE
    resposta = rng.uniform(-1, 1, n) * np.exp(-t * 6.9 / segundos)
    resposta = passa_baixa(resposta, 400.0, 1)
    resposta[: int(RATE * 0.012)] = 0.0  # pré-atraso
    resposta /= np.sqrt(np.sum(resposta ** 2))
    tamanho = len(x) + n
    fft = 1 << (tamanho - 1).bit_length()
    molhado = np.fft.irfft(np.fft.rfft(x, fft) * np.fft.rfft(resposta, fft), fft)[:tamanho]
    seco = np.concatenate([x, np.zeros(n)])
    return seco * (1 - REVERB_MISTURA) + molhado * REVERB_MISTURA * 3.0


def batida():
    rng = np.random.default_rng(2718)
    n = int(RATE * 0.7)
    som = pancada(n, 0, 1.0, rng) + pancada(n, int(RATE * 0.24), 0.75, rng)
    som = passa_baixa(som, CORTE_HZ)
    som = reverb(som, REVERB_SEGUNDOS, rng)
    som = passa_baixa(som, CORTE_HZ * 1.6, 1)  # tira o que o reverb clareou
    fim = int(RATE * 0.02)
    som[-fim:] *= np.linspace(1.0, 0.0, fim)
    return (som / np.max(np.abs(som)) * 0.95).astype(np.float32)


def main():
    os.makedirs(DIR, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "batida.f32")
        batida().tofile(raw)
        ogg = os.path.join(DIR, "batida.ogg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1",
                        "-i", raw, "-c:a", "libvorbis", "-q:a", "6", ogg], check=True)
        print("ok:", os.path.relpath(ogg, RAIZ))


if __name__ == "__main__":
    main()
