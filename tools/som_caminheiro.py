"""Gera os sons do Caminheiro (assets/sounds/caminheiro/).

batida.ogg: um coração ouvido de dentro, duas pancadas graves ("tum-tum") de
um tambor bem abafado, com passa-baixa forte (só o gravão) e um reverb curto
e escuro.

camada.ogg: a camada que soa junto com a batida só quando a criatura está
de frente para o cristal. Um brilho de cristal escuro e baixinho (um tom de
vidro com parciais inarmônicas, como uma tigela de cristal tocada de leve)
em cada pancada do "tum-tum", com um sopro de ar por cima. Tem médios e
agudos que a batida não tem, então também deixa mais claro, pelo HRTF, que
o som está bem à frente.

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

CORTE_HZ = 110.0  # passa-baixa: só o grave (batida.ogg, o timbre padrão, de frente)
## Batidas abafadas para quando o cristal está fora de frente: quanto mais
## atrás, menor o corte do passa-baixa. O jogo escolhe uma pelo ângulo.
## Índice 0 = bem atrás (mais abafada); o último nível é a batida.ogg normal.
CORTES_ABAFADOS_HZ = [52.0, 65.0, 84.0]
REVERB_SEGUNDOS = 0.6  # cauda curta, para caber entre as batidas
REVERB_MISTURA = 0.18  # pouco reverb: no grave, reverb demais embola


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
    """Reverb por convolução com uma resposta sintética: ruído denso que
    decai suave. Sem filtrar a resposta: ruído filtrado fica esparso no grave
    e faz o som "granular", como distorcido."""
    n = int(RATE * segundos)
    t = np.arange(n) / RATE
    resposta = rng.uniform(-1, 1, n) * np.exp(-t * 6.9 / segundos)
    ataque = int(RATE * 0.02)
    resposta[:ataque] *= np.linspace(0.0, 1.0, ataque)  # entra suave
    resposta /= np.sqrt(np.sum(resposta ** 2))
    tamanho = len(x) + n
    fft = 1 << (tamanho - 1).bit_length()
    molhado = np.fft.irfft(np.fft.rfft(x, fft) * np.fft.rfft(resposta, fft), fft)[:tamanho]
    seco = np.concatenate([x, np.zeros(n)])
    return seco * (1 - REVERB_MISTURA) + molhado * REVERB_MISTURA


CAMADA_TOM_HZ = 392.0  # sol: tom do cristal (as parciais são inarmônicas)
CAMADA_PARCIAIS = [(1.0, 1.0, 4.5), (2.76, 0.45, 7.0), (5.40, 0.18, 11.0), (8.93, 0.07, 16.0)]
CAMADA_CORTE_HZ = 600.0  # passa-baixa: onda quadrada abafada, só uma cor por cima do coração
## "Suga": antes de cada pancada, um ruído de caixa ao contrário que sobe e
## some num fade suave (sem ataque), como se a batida puxasse o ar.
SUGA_SEGUNDOS = 0.15
SUGA_PASSA_ALTA_HZ = 400.0
SUGA_PASSA_BAIXA_HZ = 2500.0
SUGA_PICO = 0.8  # fração da duração em que o ruído chega ao máximo; depois cai num fade
SUGA_GANHO = 0.2  # relativo à batida (pico 0,8)


def brilho(n, inicio, volume, tom, rng):
    """Um toque de cristal: parciais de tigela que decaem, ataque macio
    (sem estalo) e um batimento lento entre duas cópias quase iguais."""
    som = np.zeros(n)
    t = np.arange(n - inicio) / RATE
    ataque = np.minimum(t / 0.012, 1.0)
    for razao, ganho, decai in CAMADA_PARCIAIS:
        f = tom * razao
        fase = rng.uniform(0, 2 * np.pi)
        onda = np.sin(2 * np.pi * f * t + fase) + 0.6 * np.sin(2 * np.pi * (f + 1.3) * t + fase)
        som[inicio:] += onda * ganho * np.exp(-t * decai)
    ar = rng.uniform(-1, 1, len(t)) * np.exp(-t * 25.0) * 0.05
    som[inicio:] = (som[inicio:] + ar) * ataque * volume
    return som


def quadrada(n, inicio, volume, tom):
    """Um toque de onda quadrada com ataque macio e queda suave."""
    som = np.zeros(n)
    t = np.arange(n - inicio) / RATE
    onda = np.sign(np.sin(2 * np.pi * tom * t))
    som[inicio:] = onda * np.exp(-t * 8.0) * np.minimum(t / 0.012, 1.0) * volume
    return som


def camada():
    rng = np.random.default_rng(1618)
    n = int(RATE * 0.8)  # cabe entre as batidas (0,857 s a 70 bpm)
    lead = int(RATE * SUGA_SEGUNDOS)  # a camada acompanha a pancada, que vem depois da suga
    n += lead
    som = quadrada(n, lead, 1.0, CAMADA_TOM_HZ) + quadrada(n, lead + int(RATE * 0.24), 0.6, CAMADA_TOM_HZ * 0.75)
    som = passa_baixa(som, CAMADA_CORTE_HZ, 2)
    fim = int(RATE * 0.12)
    som[-fim:] *= np.linspace(1.0, 0.0, fim) ** 2
    som = reverb(som, 0.5, rng)[:n]
    som[-fim:] *= np.linspace(1.0, 0.0, fim)
    return (som / np.max(np.abs(som)) * 0.8).astype(np.float32)


def suga(ganho):
    """Ruído de caixa ao contrário: sobe até perto da pancada e cai num fade
    (curva de cosseno), sem corte seco."""
    rng = np.random.default_rng(7)
    n = int(RATE * SUGA_SEGUNDOS)
    x = rng.uniform(-1, 1, n)
    x = passa_baixa(x, SUGA_PASSA_BAIXA_HZ, 2)
    x = x - passa_baixa(x, SUGA_PASSA_ALTA_HZ, 2)
    u = np.arange(n) / n
    pico = SUGA_PICO
    subida = (np.minimum(u / pico, 1.0)) ** 3
    queda = np.where(u > pico, 0.5 * (1 + np.cos(np.pi * (u - pico) / (1 - pico))), 1.0)
    x *= subida * queda
    return x / np.max(np.abs(x)) * ganho


def batida(corte=CORTE_HZ, ganho_suga=0.0):
    """ganho_suga > 0: acrescenta a suga antes de cada pancada (a batida
    começa SUGA_SEGUNDOS depois do início do arquivo)."""
    rng = np.random.default_rng(2718)
    lead = int(RATE * SUGA_SEGUNDOS) if ganho_suga > 0 else 0
    n = int(RATE * 0.7) + lead
    som = pancada(n, lead, 1.0, rng) + pancada(n, lead + int(RATE * 0.24), 0.75, rng)
    som = passa_baixa(som, corte)
    som = reverb(som, REVERB_SEGUNDOS, rng)
    som = passa_baixa(som, corte * 1.6, 1)  # tira o que o reverb clareou
    if ganho_suga > 0:
        # A suga fica fora do passa-baixa grave e do reverb; some antes da pancada.
        pico = np.max(np.abs(som))
        s1 = suga(ganho_suga * pico / 0.8)
        for inicio in (0, int(RATE * 0.24)):
            som[inicio:inicio + len(s1)] += s1
    fim = int(RATE * 0.02)
    som[-fim:] *= np.linspace(1.0, 0.0, fim)
    return (som / np.max(np.abs(som)) * 0.8).astype(np.float32)  # folga contra distorção


def main():
    os.makedirs(DIR, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        sons = [("batida", lambda: batida(CORTE_HZ, SUGA_GANHO)), ("camada", camada)]
        for i, corte in enumerate(CORTES_ABAFADOS_HZ):
            # nível 0 sem suga; 1 e 2 com suga crescente (raiz da abertura)
            ganho = SUGA_GANHO * ((i / 3.0) ** 0.5)
            sons.append(("batida_abafada_%d" % i, lambda corte=corte, ganho=ganho: batida(corte, ganho)))
        for nome, gerar in sons:
            raw = os.path.join(tmp, nome + ".f32")
            gerar().tofile(raw)
            ogg = os.path.join(DIR, nome + ".ogg")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1",
                            "-i", raw, "-c:a", "libvorbis", "-q:a", "6", ogg], check=True)
            print("ok:", os.path.relpath(ogg, RAIZ))


if __name__ == "__main__":
    main()
