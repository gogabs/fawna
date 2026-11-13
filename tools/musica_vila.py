"""Gera a música de fundo do jogo, tocada por uma ocarina.

Escreve um MIDI por nível da horta (assets/music/vila_N.mid) e renderiza cada
um em .ogg com o FluidSynth (assets/sounds/musica/vila_N.ogg). Os loops têm
todos o mesmo tamanho e emendam sem estalo: a cauda da reverberação é somada
ao começo do loop.

Para mudar a música, edite as notas abaixo (ou os .mid num editor de MIDI e
rode com --so-renderizar) e rode de novo:

    python3 tools/musica_vila.py [--soundfont caminho.sf2]

Precisa de: fluidsynth, ffmpeg, python3 com mido e numpy.
"""

import argparse
import os
import subprocess
import sys
import tempfile

import mido
import numpy as np

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR_MIDI = os.path.join(RAIZ, "assets", "music")
DIR_OGG = os.path.join(RAIZ, "assets", "sounds", "musica")
SOUNDFONT = "/usr/share/sounds/sf2/FluidR3_GM.sf2"

BPM = 60
TPB = 480  # ticks por batida
COMPASSOS = 2  # 2 compassos de 4/4 = 8 s
RATE = 44100
CAUDA = 3.0  # segundos extras renderizados para a reverberação

# Programas General MIDI (contados a partir de 0).
OCARINA = 79
PIO = 123  # "Bird Tweet"

# Notas: (nota MIDI, início em batidas, duração em batidas, volume)
C3, C5, D5, E5, G5, A5 = 48, 72, 74, 76, 79, 81

MELODIA_SIMPLES = [  # dó mi sol mi, como o sininho original
    (C5, 0, 0.9, 80), (E5, 1, 0.9, 76), (G5, 2, 0.9, 84), (E5, 3, 0.9, 74),
    (C5, 4, 0.9, 78), (E5, 5, 0.9, 74), (G5, 6, 1.8, 82),
]
MELODIA_CHEIA = [  # pentatônica: dó ré mi sol lá sol mi ré
    (C5, 0, 0.9, 80), (D5, 1, 0.9, 74), (E5, 2, 0.9, 78), (G5, 3, 0.9, 84),
    (A5, 4, 1.4, 88), (G5, 5.5, 0.45, 76), (E5, 6, 0.9, 74), (D5, 7, 0.9, 70),
]
BAIXO = [(C3, 0, 3.8, 52), (C3 + 7, 4, 3.8, 48)]  # dó e sol graves, bem suaves
PASSARINHOS = [(96, 1.5, 0.4, 50), (100, 4.75, 0.3, 44), (98, 6.5, 0.4, 48)]

NIVEIS = {
    0: [(OCARINA, MELODIA_SIMPLES)],
    1: [(OCARINA, MELODIA_CHEIA)],
    2: [(OCARINA, MELODIA_CHEIA), (OCARINA, BAIXO)],
    3: [(OCARINA, MELODIA_CHEIA), (OCARINA, BAIXO), (PIO, PASSARINHOS)],
}


def escrever_midi(nivel, caminho):
    arquivo = mido.MidiFile(ticks_per_beat=TPB)
    meta = mido.MidiTrack()
    meta.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(BPM)))
    meta.append(mido.MetaMessage("track_name", name="Vila nível %d" % nivel))
    meta.append(mido.MetaMessage("end_of_track", time=COMPASSOS * 4 * TPB))
    arquivo.tracks.append(meta)
    for canal, (programa, notas) in enumerate(NIVEIS[nivel]):
        eventos = []
        for nota, inicio, dur, vel in notas:
            eventos.append((int(inicio * TPB), mido.Message("note_on", channel=canal, note=nota, velocity=vel)))
            eventos.append((int((inicio + dur) * TPB), mido.Message("note_off", channel=canal, note=nota, velocity=0)))
        eventos.sort(key=lambda e: (e[0], e[1].type == "note_on"))
        trilha = mido.MidiTrack()
        trilha.append(mido.Message("program_change", channel=canal, program=programa, time=0))
        trilha.append(mido.Message("control_change", channel=canal, control=91, value=70, time=0))  # reverb
        agora = 0
        for tick, msg in eventos:
            trilha.append(msg.copy(time=tick - agora))
            agora = tick
        trilha.append(mido.MetaMessage("end_of_track", time=0))
        arquivo.tracks.append(trilha)
    arquivo.save(caminho)


def renderizar(midi, ogg, soundfont):
    duracao = COMPASSOS * 4 * 60.0 / BPM
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "bruto.wav")
        subprocess.run(["fluidsynth", "-ni", "-q", "-r", str(RATE), "-g", "0.8",
                        "-F", wav, soundfont, midi], check=True)
        raw = os.path.join(tmp, "bruto.f32")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-ac", "1",
                        "-f", "f32le", raw], check=True)
        som = np.fromfile(raw, dtype=np.float32)
        n = int(duracao * RATE)
        som = np.pad(som, (0, max(0, n + int(CAUDA * RATE) - len(som))))
        loop = som[:n].copy()
        cauda = som[n:]
        loop[:len(cauda)] += cauda[:n]  # a reverberação do fim cai no começo
        loop *= 0.9 / max(1e-6, np.abs(loop).max())
        loop.astype(np.float32).tofile(raw)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE),
                        "-ac", "1", "-i", raw, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--soundfont", default=SOUNDFONT)
    p.add_argument("--so-renderizar", action="store_true",
                   help="usa os .mid que já existem (editados à mão)")
    args = p.parse_args()
    if not os.path.exists(args.soundfont):
        sys.exit("Soundfont não encontrado: %s" % args.soundfont)
    os.makedirs(DIR_MIDI, exist_ok=True)
    os.makedirs(DIR_OGG, exist_ok=True)
    for nivel in NIVEIS:
        midi = os.path.join(DIR_MIDI, "vila_%d.mid" % nivel)
        if not args.so_renderizar:
            escrever_midi(nivel, midi)
        ogg = os.path.join(DIR_OGG, "vila_%d.ogg" % nivel)
        renderizar(midi, ogg, args.soundfont)
        print("ok:", os.path.relpath(ogg, RAIZ))


if __name__ == "__main__":
    main()
