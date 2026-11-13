# Sons

- `world/`: sons escolhidos do "World Sounds Audio Pack", licença CC0 1.0 segundo o `license.txt` do pacote (copiado em `world/license.txt`). Para adicionar mais, inclua o arquivo no `MANIFEST` e rode `./tools/copiar_sons.ps1` (padrão: `D:\Áudio\world`).
- `cc0/serrote.ogg`: um golpe de serrote recortado de ["Saw" (BigSoundBank, CC0)](https://bigsoundbank.com/saw-s0016.html). Se não existir, a carpintaria usa batidas de madeira.
- A lista de sons usados está em `client/sounds.gd` (`MANIFEST`). Sem os arquivos, o jogo usa sons gerados por código.

## Música de fundo (musica/)

`musica/vila_0.ogg` a `vila_3.ogg` são a música de fundo do jogo, tocada por uma
ocarina, um arquivo por nível da horta. São gerados por `tools/musica_vila.py`
a partir dos MIDIs em `assets/music/`, com o soundfont FluidR3_GM (licença
MIT). Composição do próprio projeto. Para mudar a música, edite as notas no
script (ou os .mid) e rode o script de novo.
