"""Gera a música de fundo dark fantasy (assets/sounds/musica/sombria.ogg).

Lenta e esparsa: um bordão grave de cordas em quintas abertas, um coro bem
baixo e frases soltas de shakuhachi, em ré menor (eólio). A ideia é um lugar
belo, mas selvagem e indiferente, sem chegar a ser terror. O loop tem
16 compassos e emenda sem estalo (a reverberação do fim cai no começo).

    python3 tools/musica_sombria.py [--soundfont caminho.sf2]

Precisa de: fluidsynth, ffmpeg, python3 com mido e numpy. Usa as funções de
renderização de tools/musica_vila.py.
"""

import argparse
import os
import sys

import mido

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import musica_vila as base  # noqa: E402

BPM = 48
COMPASSOS = 16  # 64 batidas = 80 s

CORDAS, CORO, SINO, SHAKUHACHI = 49, 52, 14, 77

D2, F2, G2, A2, Bb1, C2 = 38, 41, 43, 45, 34, 36
D3, A3, C4, D4, E4, F4, G4, A4, Bb3 = 50, 57, 60, 62, 64, 65, 67, 69, 58
C5, D5, E5, F5 = 72, 74, 76, 77

# (nota, início em batidas, duração em batidas, volume)
BORDAO = []
for inicio, (raiz, quinta) in zip(range(0, 64, 16), [(D2, A2), (C2, G2), (D2, A2), (Bb1, F2)]):
    BORDAO += [(raiz, inicio, 15.8, 46), (quinta, inicio + 2, 13.8, 38)]

CORO_NOTAS = []
for inicio, (a, b) in zip(range(0, 64, 16), [(D4, A4), (C4, G4), (D4, A4), (Bb3, F4)]):
    CORO_NOTAS += [(a, inicio + 4, 11.5, 30), (b, inicio + 6, 9.5, 26)]

SINOS = [(D3, 0, 8, 34), (A3, 32, 8, 28)]

FRASES = [
    (A4, 6, 3, 58), (C5, 9.5, 1.5, 52), (D5, 11, 4, 60), (C5, 15.5, 0.5, 46), (A4, 16, 3, 50),
    (F4, 34, 2, 52), (G4, 36, 1, 48), (A4, 37, 4, 56), (E4, 42, 2, 46), (D4, 44, 6, 50),
    (D5, 50, 2, 54), (F5, 52, 1.5, 58), (E5, 53.5, 0.5, 44), (D5, 54, 3, 52), (A4, 58, 4, 46),
]

TRILHAS = [(CORDAS, BORDAO), (CORO, CORO_NOTAS), (SINO, SINOS), (SHAKUHACHI, FRASES)]


def escrever_midi(caminho):
    arquivo = mido.MidiFile(ticks_per_beat=base.TPB)
    meta = mido.MidiTrack()
    meta.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(BPM)))
    meta.append(mido.MetaMessage("track_name", name="Fawna, fundo sombrio"))
    meta.append(mido.MetaMessage("end_of_track", time=COMPASSOS * 4 * base.TPB))
    arquivo.tracks.append(meta)
    for canal, (programa, notas) in enumerate(TRILHAS):
        eventos = []
        for nota, inicio, dur, vel in notas:
            eventos.append((int(inicio * base.TPB), mido.Message("note_on", channel=canal, note=nota, velocity=vel)))
            eventos.append((int((inicio + dur) * base.TPB), mido.Message("note_off", channel=canal, note=nota, velocity=0)))
        eventos.sort(key=lambda e: (e[0], e[1].type == "note_on"))
        trilha = mido.MidiTrack()
        trilha.append(mido.Message("program_change", channel=canal, program=programa, time=0))
        trilha.append(mido.Message("control_change", channel=canal, control=91, value=110, time=0))  # muito reverb
        agora = 0
        for tick, msg in eventos:
            trilha.append(msg.copy(time=tick - agora))
            agora = tick
        trilha.append(mido.MetaMessage("end_of_track", time=0))
        arquivo.tracks.append(trilha)
    arquivo.save(caminho)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--soundfont", default=base.SOUNDFONT)
    p.add_argument("--so-renderizar", action="store_true", help="usa o .mid que já existe (editado à mão)")
    args = p.parse_args()
    os.makedirs(base.DIR_MIDI, exist_ok=True)
    os.makedirs(base.DIR_OGG, exist_ok=True)
    midi = os.path.join(base.DIR_MIDI, "sombria.mid")
    if not args.so_renderizar:
        escrever_midi(midi)
    # A renderização de musica_vila usa os globais de lá para a duração.
    base.BPM, base.COMPASSOS, base.CAUDA = BPM, COMPASSOS, 8.0
    ogg = os.path.join(base.DIR_OGG, "sombria.ogg")
    base.renderizar(midi, ogg, args.soundfont)
    print("ok:", os.path.relpath(ogg, base.RAIZ))


if __name__ == "__main__":
    main()
