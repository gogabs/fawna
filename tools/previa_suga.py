"""Prévias do ataque "de caixa invertido" da batida do Caminheiro: antes de
cada uma das duas pancadas do "tum-tum", um ruído de caixa tocado ao
contrário (sobe e corta na pancada), como se a batida sugasse o ar.

    python3 tools/previa_suga.py SAIDA_DIR

Estéreo simples, sem HRTF; a batida gira de 180° a 0° como nas outras prévias.
"""

import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import som_caminheiro as s  # noqa: E402
import previa_caminheiro as p  # noqa: E402

RATE = s.RATE


def ruido_invertido(duracao, passa_alta, passa_baixa, curva=3.0, seed=7):
    """Caixa ao contrário: ruído filtrado que cresce até a pancada e corta."""
    rng = np.random.default_rng(seed)
    n = int(RATE * duracao)
    x = rng.uniform(-1, 1, n)
    x = s.passa_baixa(x, passa_baixa, 2)
    x = x - s.passa_baixa(x, passa_alta, 2)
    env = (np.arange(n) / n) ** curva
    x *= env
    fim = int(RATE * 0.004)
    x[-fim:] *= np.linspace(1.0, 0.0, fim)  # corte seco, sem estalo
    return x / np.max(np.abs(x))


def montar(batida, camada, suga, lead, ganho_suga, nivel_camada=True):
    """Toca as 15 batidas (180°..0°). A suga sobe nos "lead" s antes de cada
    pancada (a primeira em 0 e a segunda em 0,24 s); a batida entra "lead" s
    depois do começo do ciclo."""
    intervalo = int(RATE * 60 / 70)
    saida = np.zeros((intervalo * 16, 2))
    pos = 0
    batidas = [s.batida(c) for c in s.CORTES_ABAFADOS_HZ] + [s.batida()]
    for off in [180, 135, 90, 45, 0]:
        ab = p.abertura(off)
        b = batidas[round(ab * 3)] * 10 ** (p.ab_db(ab) / 20)
        ang = np.radians(off) + 0.15 * np.sin(2 * np.radians(off))
        pan = np.sin(ang) * 0.5 + 0.5
        for _ in range(3):
            faixas = [(b, int(RATE * lead), 1.0)]
            for inicio in (0.0, 0.24):
                faixas.append((suga, int(RATE * inicio), ganho_suga * ab ** 0.5))
            if camada is not None and off <= 45:
                faixas.append((camada, int(RATE * lead), 10 ** ((-17.0 + 8.0) / 20)))
            for faixa, desloc, g in faixas:
                m = faixa * g
                a = pos + desloc
                saida[a:a + len(m), 0] += m * np.cos(pan * np.pi / 2)
                saida[a:a + len(m), 1] += m * np.sin(pan * np.pi / 2)
            pos += intervalo
    return (saida / np.max(np.abs(saida)) * 0.8).astype(np.float32)


def main():
    destino = sys.argv[1]
    os.makedirs(destino, exist_ok=True)
    quadrada = p.camada_variante("quadrada", 600.0)
    # nome: (duração, passa-alta, passa-baixa, curva, ganho)
    variantes = {
        "suga_curta": (0.07, 1500, 6000, 2.5, 0.35, False),
        "suga_media": (0.13, 1000, 5000, 3.0, 0.35, False),
        "suga_longa": (0.22, 800, 4000, 3.0, 0.3, False),
        "suga_escura": (0.13, 400, 2500, 3.0, 0.45, False),
        "suga_media_com_quadrada": (0.13, 1000, 5000, 3.0, 0.35, True),
        "suga_escura_com_quadrada": (0.13, 400, 2500, 3.0, 0.45, True),
    }
    for nome, (dur, ha, ba, curva, ganho, com_camada) in variantes.items():
        suga = ruido_invertido(dur, ha, ba, curva)
        # a suga da 2ª pancada termina na pancada: começa em 0,24-dur
        lead = dur
        som = montar(None, quadrada if com_camada else None, suga, lead, ganho)
        raw = os.path.join(destino, nome + ".f32")
        som.tofile(raw)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", raw,
                        "-c:a", "libvorbis", "-q:a", "5", os.path.join(destino, nome + ".ogg")], check=True)
        os.remove(raw)
        print("ok", nome)


if __name__ == "__main__":
    main()
