"""Prévias de áudio do Caminheiro para ouvir antes de decidir (estéreo
simples, sem HRTF: só um pan, então serve para comparar timbres, não o 3D).

    python3 tools/previa_caminheiro.py SAIDA_DIR

Gera, para cada variante da camada de cristal, um arquivo com a batida
girando de trás para a frente: 180°, 135°, 90°, 45° e 0° (3 batidas em cada).
A batida abre (volume e passa-baixa) e a camada entra perto da frente.
"""

import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import som_caminheiro as s  # noqa: E402

RATE = s.RATE


def camada_variante(forma, corte):
    rng = np.random.default_rng(1618)
    n = int(RATE * 0.8)
    t = np.arange(n) / RATE

    def toque(inicio, volume, tom):
        som = np.zeros(n)
        u = np.arange(n - inicio) / RATE
        if forma == "sino":
            return s.brilho(n, inicio, volume, tom, rng)
        if forma == "triangulo":
            fase = (tom * u) % 1.0
            onda = 2 * np.abs(2 * fase - 1) - 1
            env = np.exp(-u * 6.0)
        elif forma == "serra":
            onda = 2 * ((tom * u) % 1.0) - 1
            env = np.exp(-u * 7.0)
        elif forma == "quadrada":
            onda = np.sign(np.sin(2 * np.pi * tom * u))
            env = np.exp(-u * 8.0)
        else:  # fm: sino por modulação de frequência
            mod = np.sin(2 * np.pi * tom * 1.41 * u) * 2.2 * np.exp(-u * 9.0)
            onda = np.sin(2 * np.pi * tom * u + mod)
            env = np.exp(-u * 5.0)
        som[inicio:] = onda * env * np.minimum(u / 0.012, 1.0) * volume
        return som

    som = toque(0, 1.0, s.CAMADA_TOM_HZ) + toque(int(RATE * 0.24), 0.6, s.CAMADA_TOM_HZ * 0.75)
    som = s.passa_baixa(som, corte, 2)
    fim = int(RATE * 0.12)
    som[-fim:] *= np.linspace(1.0, 0.0, fim) ** 2
    som = s.reverb(som, 0.5, rng)[:n]
    return (som / np.max(np.abs(som)) * 0.8).astype(np.float32)


def abertura(off):
    t = min(max((off - 22.5) / (135.0 - 22.5), 0.0), 1.0)
    return 1.0 - t * t * (3.0 - 2.0 * t)


def montar(camada):
    batidas = [s.batida(c) for c in s.CORTES_ABAFADOS_HZ] + [s.batida()]
    intervalo = int(RATE * s.BEAT_INTERVAL) if hasattr(s, "BEAT_INTERVAL") else int(RATE * 60 / 70)
    saida = np.zeros((int(RATE * 60 / 70 * 15 + RATE), 2))
    pos = 0
    for off in [180, 135, 90, 45, 0]:
        for _ in range(3):
            ab = abertura(off)
            b = batidas[round(ab * 3)] * 10 ** (ab_db(ab) / 20)
            camada_gain = 0.0
            if off <= 45:
                near = 1.0 - min(max((off - 22.5) / 22.5, 0.0), 1.0)
                camada_gain = 10 ** ((-17.0 + (1 - near) * -9.0 + 8.0) / 20)
            # pan simples: lado pelo seno do ângulo (ângulo alargado como no jogo)
            ang = np.radians(off) + 0.15 * np.sin(2 * np.radians(off))
            pan = np.sin(ang) * 0.5 + 0.5  # 0 esq, 1 dir (cristal à direita)
            for faixa, g in [(b, 1.0), (camada, camada_gain)]:
                if g == 0.0:
                    continue
                m = faixa * g
                saida[pos:pos + len(m), 0] += m * np.cos(pan * np.pi / 2)
                saida[pos:pos + len(m), 1] += m * np.sin(pan * np.pi / 2)
            pos += intervalo
    return (saida / max(np.max(np.abs(saida)), 1e-6) * 0.8).astype(np.float32)


def ab_db(abertura_valor):
    return (1.0 - abertura_valor) * -7.0


def main():
    destino = sys.argv[1]
    os.makedirs(destino, exist_ok=True)
    variantes = [("sino_900", "sino", 900.0), ("sino_1600", "sino", 1600.0), ("triangulo_900", "triangulo", 900.0),
                 ("triangulo_1500", "triangulo", 1500.0), ("serra_700", "serra", 700.0), ("serra_1200", "serra", 1200.0),
                 ("quadrada_600", "quadrada", 600.0), ("fm_1100", "fm", 1100.0), ("fm_2000", "fm", 2000.0)]
    for nome, forma, corte in variantes:
        som = montar(camada_variante(forma, corte))
        raw = os.path.join(destino, nome + ".f32")
        som.tofile(raw)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", raw,
                        "-c:a", "libvorbis", "-q:a", "5", os.path.join(destino, "camada_" + nome + ".ogg")], check=True)
        os.remove(raw)
        print("ok", nome)


if __name__ == "__main__":
    main()
