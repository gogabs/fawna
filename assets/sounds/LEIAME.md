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
curto e escuro já aplicados no arquivo. `caminheiro/camada.ogg` é o brilho de
cristal que soa por cima da batida quando a criatura está de frente para o
cristal. Os dois são gerados por `tools/som_caminheiro.py` (sons do próprio
projeto).

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

## Recursos coletáveis (recursos/)

Sons para achar e recolher os recursos (`Sounds.resource_loop`, `pickup`,
`bamboo_knock`, `bamboo_fall`). Escolhidos pelo Gabs (2026-11-14):
`bambu_golpe_1..3`, `bambu_queda_1..3`, `coleta_bambu_1..4`,
`coleta_lenha_1..4`, `coleta_argila_1..3` e `coleta_frutas_1..3`; a cada vez
um é sorteado, sem repetir o anterior. Ainda fora do repositório, até o Gabs
autorizar publicar: copie para `assets/sounds/recursos/` para ouvir.

Loops para achar de ouvido (em 3D, na posição do recurso): `amb_bambu`,
`amb_frutas`. Os galhos caídos (madeira média e pequena) não têm loop próprio; `coleta_lenha` soa ao catá-los. A argila não tem loop: fica
sempre na beira da água, que já soa. Sem os arquivos, o jogo usa sons do
pacote `world/` e sons gerados por código (`client/sound_bank.gd`).

## Recursos, machado e bolsa (recursos/, ferramentas/, menu/)

Escolhidos pelo Gabs (2026-11-14) entre candidatos do Freesound, recortados,
filtrados e nivelados; publicados com autorização dele. Todos CC0 1.0.

- `ferramentas/machado_golpe_1..3.ogg`: "Whoosh - 60cm ish stick" ([Sadiquecat, 855840](https://freesound.org/s/855840/)).
- `ferramentas/machado_impacto_1..4.ogg`: "Axe chopping wood" ([xkeril, 753925](https://freesound.org/s/753925/)).
- `ferramentas/bolsa_abrir.ogg`, `bolsa_mexer.ogg`, `bolsa_fechar.ogg`: "Leather bag handling" ([vintage2005, 435533](https://freesound.org/s/435533/)).
- `ferramentas/empunhar.ogg`, `guardar.ogg`, `amolar_extra.ogg`: "Scythe Sharpen" ([CapsLok, 181921](https://freesound.org/s/181921/)), três passadas na pedra de amolar.
- `menu/menu_navegar.ogg`: "tapping kindling" ([itinerantmonk108, 737557](https://freesound.org/s/737557/)).
- `menu/menu_abrir.ogg` e `menu/menu_fechar.ogg`: `dlgopen.ogg` e `dlgclose.ogg` do "World Sounds Audio Pack" (o mesmo de `world/`, CC0 1.0, ver `world/license.txt`), recortados e nivelados. Publicados com autorização do Gabs (2026-11-15).
- `recursos/bambu_golpe_1..3.ogg`: o mesmo "tapping kindling" (toc oco).
- `recursos/bambu_queda_1.ogg`: "Falling Bamboo" ([AyeJayCee, 326299](https://freesound.org/s/326299/)); `bambu_queda_2..3.ogg`: "BambooCracking" ([klakmart, 108263](https://freesound.org/s/108263/)).
- `recursos/coleta_bambu_1..4.ogg`: "Wood Jostling" ([ErikH2000, 213066](https://freesound.org/s/213066/)).
- `recursos/coleta_lenha_1..4.ogg`: "Snapping small twigs gathering wood" ([Alex_hears_things, 636854](https://freesound.org/s/636854/)).
- `recursos/coleta_argila_1..3.ogg`: "MudSquelch" ([ahill86, 207142](https://freesound.org/s/207142/)).
- `recursos/coleta_frutas_1..3.ogg`: "Rustling foliage" ([DDT197, 445788](https://freesound.org/s/445788/)) com o estalo de "pencil snap..." ([kyles, 637746](https://freesound.org/s/637746/)).
- `recursos/amb_bambu.ogg` e `recursos/amb_frutas.ogg`: gerados por código para o projeto (`tools/sons_recursos.py`): madeira oca batendo, e farfalhar baixinho com gotinhas ascendentes (a frutinha).
- Sem som próprio, de propósito: o emissor da argila (a água por perto já soa) e o dos galhos caídos ao pé das árvores.

## Árvores

Ainda sem gravações: o golpe no tronco, o rangido dos últimos golpes e a
queda são gerados por código (`SoundBank.tree_knock`, `tree_creak`,
`tree_fall`), e a madeira recolhida usa os `coleta_bambu_*`. Esbarrar numa
árvore toca `world/walltree.ogg`. Quando houver gravações escolhidas, basta
pôr em `recursos/` com os nomes `arvore_golpe_1..4.ogg`,
`arvore_rangido_1..3.ogg`, `arvore_queda_1..3.ogg` e `coleta_madeira_1..4.ogg`:
o jogo passa a usá-las sozinho.

## Cavalinhos-da-bruma (cavalos/)

Sons dos cavalos selvagens (`client/horse_sounds.gd`), escolhidos pelo Gabs
em várias rodadas de comparação. Recortados, limpos de ruído, em mono 48 kHz.
Publicados com autorização do Gabs (2026-11-22).

- `casco_<chão>_<n>.ogg`: uma pisada. Cada uma junta um casco gravado e uma
  pisada do "World Sounds Audio Pack" (CC0, ver `world/`) num tom mais grave:
  grama com `grassstep`/`brushstep`, terra com `dirtstep`, neve com
  `deepsnowstep` (casco abafado), madeira com `bridge2step`/`creekywoodstep`.
  Grama, terra e neve com o casco um pouco mais baixo e a cauda suavizada.
- `galope_<chão>_<n>.ogg`: uma passada inteira de galope: quatro batidas
  (na grama, as mesmas pisadas do passo), o corpo (galope gravado, grave e baixo) e uma bufada curta de fôlego.
- `relincho_<n>`, `bufo_<n>`, `manso_<n>` (relincho manso), `pasto_<n>`.
- `corpo_<n>` (o corpo assentando no lombo, ao montar) e `toque_<n>` (os
  calcanhares no lombo, ao apertar W montado): gerados por código, sem gravação.

Gravações de origem, todas no Freesound:

- Relinchos: ["Horse_Whinny", de foxen10](https://freesound.org/s/149024/) (CC0),
  ["horse's whinny", de Kubuzz](https://freesound.org/s/347036/) (CC0),
  ["horse neigh shortened", de shadoWisp](https://freesound.org/s/269571/) (CC0),
  ["Horse Whinny, Close, A", de InspectorJ](https://freesound.org/s/419231/) (CC BY 4.0).
- Bufos: ["horse snort", de bruno.auzet](https://freesound.org/s/538697/) (CC0),
  ["Horse (snort) 3", de o_ciz](https://freesound.org/s/475483/) (CC0),
  ["horse snort, breathe, eat", de Garuda1982](https://freesound.org/s/531429/) (CC0),
  ["horse snort 7", de ERH](https://freesound.org/s/32044/) (CC BY),
  ["Horse Snort 2", de GoodListener](https://freesound.org/s/322454/) (CC BY).
- Relincho manso: ["Horses, Soft Nicker", de TheKingOfGeeks360](https://freesound.org/s/861234/) (CC0),
  ["Horse Nicker 2", de GoodListener](https://freesound.org/s/322449/) (CC BY).
- Pastando: ["Horse Eating", de crattray1997](https://freesound.org/s/578138/) (CC BY).
- Cascos: ["Horse Clip Clopping Downhill", de swiftoid](https://freesound.org/s/182504/) (CC0),
  ["horse steps 01", de gastonsaenz](https://freesound.org/s/362959/) (CC BY).
- Galope: ["Foley Horse Galloping", de StephenSaldanha](https://freesound.org/s/165532/) (CC0).

Obrigado a todos. Os gravados CC BY pedem crédito: InspectorJ, ERH,
GoodListener, crattray1997 e gastonsaenz.
