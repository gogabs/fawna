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

## Bússola (bussola/)

Cliques da bússola, gerados por `tools/sons_bussola.py` (sons do próprio
projeto): `norte.ogg` agudo, `sul.ogg` grave, `lateral.ogg` para leste e
oeste, `colateral.ogg` abafado para as diagonais.

## Música de fundo sombria (musica/sombria.ogg)

Música dark fantasy do jogo: bordão grave de cordas, coro baixo, sinos e
frases de shakuhachi, em ré menor. Gerada por `tools/musica_sombria.py`
(MIDI em `assets/music/sombria.mid`, soundfont FluidR3_GM, licença MIT).
Composição do próprio projeto. A musiquinha de ocarina (`musica/vila_*.ogg`)
continua guardada; `USE_OCARINA` em `autoload/music.gd` a traz de volta.

## Foley de movimento (foley/)

Sons da roupa de algodão e da tornozeleira de conchas da criatura: giro,
início e parada do movimento, farfalhar contínuo e conchas a cada dois passos.
Os outros jogadores soam igual, posicionados em 3D. Publicados com autorização
do Gabs (2026-11-14).

- `farfalhar_1..7.ogg`, `inicio_amigo.ogg`, `parada_amigo.ogg`: farfalhares de
  roupa gravados por um amigo do Gabs, cedidos ao projeto sem exigência de
  atribuição.
- `giro_1..3.ogg`, `inicio_sintetico.ogg`, `parada_sintetica.ogg`: gerados por
  código para o projeto.
- `tornozeleira_concha.ogg`: trecho (1,4 a 2,3 s, passa-baixa 6,5 kHz) de
  ["SeaShell_01", de agoniasboy no Freesound](https://freesound.org/s/152772/),
  CC0. Obrigado, agoniasboy.
- `tornozeleira_1..10.ogg`: sacudidas novas montadas com os cliques recortados
  dessa mesma gravação, com altura e ritmo sorteados.

## Caminheiro (caminheiro/)

`caminheiro/batida.ogg` é a batida do Caminheiro: um coração ouvido de dentro,
duas pancadas graves de tambor abafado, com passa-baixa forte e um reverb
curto e escuro já aplicados no arquivo. Gerado por `tools/som_caminheiro.py`
(som do próprio projeto).
