"""Gera os cliques da bússola (assets/sounds/bussola/).

Norte é um clique agudo, sul um grave, leste e oeste um clique médio igual, e
os pontos colaterais (nordeste, sudeste...) um clique médio mais abafado.
O jogo toca o clique em 3D, na direção para onde a criatura passou a olhar.

    python3 tools/sons_bussola.py

Precisa de: python3 com numpy, e ffmpeg.
"""

import os
import subprocess
import tempfile

import numpy as np

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(RAIZ, "assets", "sounds", "bussola")
RATE = 44100

# nome: (frequência, decaimento em segundos, volume, abafado)
CLIQUES = {
    "norte": (2200.0, 0.022, 0.9, False),
    "sul": (520.0, 0.045, 1.0, False),
    "lateral": (1100.0, 0.03, 0.85, False),
    "colateral": (1100.0, 0.03, 0.55, True),
}


def clique(freq, decay, volume, abafado):
    n = int(RATE * max(0.12, decay * 6))
    t = np.arange(n) / RATE
    env = np.exp(-t / decay)
    attack = int(RATE * (0.004 if abafado else 0.0008))
    env[:attack] *= np.linspace(0.0, 1.0, attack)
    som = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 2.01 * t) * np.exp(-t / (decay * 0.5))
    if not abafado:
        rng = np.random.default_rng(7)
        ruido = rng.uniform(-1, 1, n) * np.exp(-t / 0.002)
        som += 0.5 * ruido
    som *= env
    if abafado:
        # passa-baixas simples: tira o brilho e deixa o clique "fofo"
        for _ in range(3):
            som = np.convolve(som, np.ones(9) / 9, mode="same")
    som *= volume / max(1e-6, np.abs(som).max())
    return som.astype(np.float32)


def main():
    os.makedirs(DIR, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for nome, args in CLIQUES.items():
            raw = os.path.join(tmp, nome + ".f32")
            clique(*args).tofile(raw)
            ogg = os.path.join(DIR, nome + ".ogg")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1",
                            "-i", raw, "-c:a", "libvorbis", "-q:a", "6", ogg], check=True)
            print("ok:", os.path.relpath(ogg, RAIZ))


if __name__ == "__main__":
    main()
