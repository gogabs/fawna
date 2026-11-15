# Sons

- `world/`: sons escolhidos do "World Sounds Audio Pack", licença CC0 1.0 segundo o `license.txt` do pacote (copiado em `world/license.txt`). Para adicionar mais, inclua o arquivo no `MANIFEST` e rode `./tools/copiar_sons.ps1` (padrão: `D:\Áudio\world`).
- A lista de sons usados está em `client/sounds.gd` (`MANIFEST`). Sem os arquivos, o jogo usa sons gerados por código.

## Música de fundo (musica/)

`musica/vila_0.ogg` a `vila_3.ogg` são a música de fundo do jogo, tocada por uma
ocarina, um arquivo por nível (guardada, sem tocar). São gerados por `tools/musica_vila.py`
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

## Pássaros (passaros/)

Cantos, chamados e asas dos pássaros (`client/bird_songs.gd`). Os nomes seguem
`<espécie>_<voz>_<frase>`, `asas_<n>` e `carrica_alarme`. Sem os arquivos, o
jogo gera os sons por código. Publicados com autorização do Gabs (2026-11-14).

- Gravados por um amigo do Gabs, cedidos ao projeto sem exigência de
  atribuição, recortados em 48 kHz: `asas_2..11`, `carrica_3..5`, `sabia_3..4`,
  `corvo_*`, `coruja_*`, `gaviao_*`, `periquito_*`.
- Recortes de gravações CC0 do Freesound:
  - `sabia_0_*`: [811988](https://freesound.org/s/811988/) (melro)
  - `sabia_1_*`: [854987](https://freesound.org/s/854987/) (rouxinol)
  - `sabia_2_*`: [785669](https://freesound.org/s/785669/) (tordo-músico)
  - `carrica_0_*` e `carrica_alarme`: [836392](https://freesound.org/s/836392/) (corruíra, de newtad1)
  - `carrica_1_*`: [703254](https://freesound.org/s/703254/) (chapim)
  - `rolinha_0_*`: [735366](https://freesound.org/s/735366/) (pomba)
  - `asas_0`: [330967](https://freesound.org/s/330967/); `asas_1`: [561009](https://freesound.org/s/561009/)
