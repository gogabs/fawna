# Fawna

Jogo cooperativo e acessível (pensado primeiro para pessoas cegas) em que você é uma criaturinha híbrida ajudando a construir uma comunidade sustentável num mundo solarpunk. Todos jogam num único mundo compartilhado, que é gerado proceduralmente e cresce aos poucos, sem que ninguém destrua o que outra pessoa construiu.

Documento de design: <https://claude.ai/artifact/YTAHWweYCcywSAJtDc1GMh>

## Como rodar

O projeto usa **Godot 4.6 ou mais novo** e **GDScript**.

1. (Opcional) Copie os sons do pacote World Sounds: `./tools/copiar_sons.ps1` (veja `assets/sounds/LEIAME.md`).
1. Instale as extensões nativas (fala e áudio 3D), que não ficam no repositório por serem grandes:
   - Windows (PowerShell): `./tools/instalar_extensoes.ps1`
   - Linux/macOS: `sh tools/instalar_extensoes.sh`
2. Abra a pasta no editor do Godot e aperte F5. Se for rodar só pela linha de comando, rode antes `godot --headless --path . --import` uma vez.

O jogo funciona sem as extensões, com a voz e o áudio 3D do próprio Godot, mas fica bem melhor com elas. No menu principal:

- **Conectar:** entra no servidor configurado (padrão da versão de testes: `26.127.36.156`, pela VPN).
- **Opções:** muda seu nome e o servidor (`ip` ou `ip:porta`; porta padrão 7350). Fica salvo em `user://config.cfg`.
- **Sair.**

Para hospedar, rode o servidor dedicado ou `--host` pela linha de comando (abaixo).

### Pela linha de comando

```sh
# Servidor dedicado (sem tela)
godot --headless --path . -- --server --port=7350 --seed=42

# Hospedar e jogar
godot --path . -- --host --name=Gabs

# Entrar num servidor (ex.: pelo IP da VPN)
godot --path . -- --join=10.0.0.5 --name=Lua
```

Opções: `--server`, `--host`, `--join=ENDEREÇO`, `--port=N`, `--name=NOME`, `--seed=N` e `--auto=N,L,ARREDORES,SAIR` (comandos automáticos, usados nos testes).

## Controles

| Ação | Tecla |
| --- | --- |
| Andar para frente / para trás | W / S |
| Passo para o lado | A / D |
| Girar 45° para a esquerda / direita | Q / E |
| Menu flutuante (Caminheiro, Bolsa, Equipamento) | setas: ← / → escolhem, ↑ confirma, ↓ volta |
| Para onde estou olhando | F |
| Coletar | Espaço |
| O que há na bolsa e nas mãos | I |
| Golpear com o machado (empunhado) | J |
| Ajuda (lista de comandos) | H |
| Ouvir os arredores | Tab |
| Onde estou | C |
| Quem está no mundo | P |
| Repetir a última fala | R |

O jogo é em primeira pessoa: a criatura anda livremente (não mais de casa
em casa) e olha para uma de 8 direções. A cada giro, uma bússola dá um
clique: agudo no norte, grave no sul, igual no leste e no oeste, e abafado
nas diagonais. A bússola é um relógio em volta da cabeça: cada direção soa
sempre na sua hora (norte ao meio-dia, à frente; leste às 3; sul às 6, atrás;
oeste às 9), e o que muda é qual delas toca.

O mundo não tem bordas. Ele é dividido em regiões grandes (72 m de lado),
cada uma com uma característica só: bosque de micélio, pradaria de
girassóis ou lagoa das vitórias-régias. O que há dentro delas é gerado aos
pedaços, conforme alguém chega perto. Trilhas de terra ligam o ponto de
encontro de cada região aos das vizinhas, com pontes onde cruzam a água; a
Origem (nome provisório) é o ponto de encontro da primeira região. As trilhas são a base para o
Caminheiro e para os caminhos dos NPCs. As falas dizem onde as coisas
estão em relação a você: "árvore, à frente e à direita, 3 metros".

## Menu das setas e o Caminheiro

As setas não movem a criatura: elas operam um menu flutuante, sempre ativo.
← e → passam pelas opções, ↑ confirma e ↓ volta. As opções são o
**Caminheiro** (o único destino, por enquanto, é a Origem), a **Bolsa** e o
**Equipamento**.

### Bolsa e Equipamento

A **Bolsa** lista o que a criatura carrega, agrupado: "Argila, 2". Itens sem
ação só repetem o nome. Alguns itens têm ação: o **machado** (toda criatura
chega ao mundo com um) tem **Empunhar**, que o tira da bolsa e o põe nas mãos.
O **Equipamento** mostra o que está nas mãos ("mãos livres" se nada), com o
botão **Guardar**, que devolve o item à bolsa. Com o machado empunhado, **J**
golpeia.

Quem decide é o servidor: o cliente pede para empunhar ou guardar, e o
servidor confere, muda a bolsa e as mãos e responde. A bolsa e o que está nas
mãos ficam salvos no mundo, pelo nome da criatura, e sobrevivem a reconexões.

O Caminheiro é um pequeno cristal que brilha azul na direção que o coração
manda: ele rastreia um lugar do mapa. Ao acender, traça a rota pelas
trilhas e pontes (`shared/wayfinder.gd`); se você estiver fora de uma trilha,
o primeiro trecho é o caminho mais rápido até a trilha mais próxima. Cada
curva da rota é um beacon, que bate como um coração (um tambor bem abafado)
vindo da direção a seguir, a 70 batidas por minuto. Ao chegar num
beacon, um woosh voa na direção do próximo, e as batidas recomeçam de lá. Na
Origem, o cristal se apaga. Se você se afastar muito da rota, ela é traçada de
novo; "Apagar o cristal" aparece no menu enquanto ele está aceso.

## Como se joga (por enquanto)

1. Procure os recursos de ouvido e aperte **Espaço** perto deles para pôr na bolsa. O bambu, os gravetos e as frutas têm um som baixinho e próprio, em 3D:
   - **Touceira de bambu** (bosque e lagoa; rara na pradaria): os colmos batem e rangem ao vento. Não se recolhe com a mão: com o machado empunhado, golpeie com **J** (de 3 a 5 golpes, conforme a touceira). No último golpe ela cai, e aí o Espaço recolhe 3 bambus. Golpes deixados pela metade se perdem depois de 3 minutos.
   - **Gravetos** no chão (sobretudo no bosque): estalidos secos. Dão 2 lenhas.
   - **Argila**, só na beira da água (margens das lagoas e dos riachos). Não tem som próprio: a água ao lado guia até ela. Dá 1 argila.
   - **Arbusto com frutas**, raro (uns poucos por região): moscas rondando. Dá 2 frutas.

   O que é recolhido some (sem som e sem fala no Tab) e rebrota com o tempo: gravetos em 5 minutos, argila em 8, bambu em 15 e frutas em 30. O mundo é um só, então o que alguém colheu some para todos. As regras ficam em `shared/harvest.gd`.
2. A Origem, no centro do mundo, é o ponto de partida. Os minigames de profissão e a horta comunitária saíram para serem refeitos com outra roupagem.

O servidor salva o mundo em `user://mundo.json` (no Windows, `%APPDATA%\Godot\app_userdata\Fawna`). Use `--novo-mundo` para recomeçar ou `--mundo=caminho` para outro arquivo.

## Fala e leitores de tela

Os menus usam nós nativos do Godot, que o leitor de tela lê sozinho. Os anúncios do jogo passam pelo autoload `Speech`:

1. Se o [Prism](https://github.com/ethindp/prism) estiver instalado, a fala vai para o leitor de tela da pessoa (NVDA, JAWS, VoiceOver, Orca...) ou para um motor de voz.
2. Sem o Prism, o jogo usa a voz embutida do Godot.
3. Toda fala também é impressa no console com o prefixo `[fala]`.

Para instalar o Prism, baixe `prismatoid-gdextension` na [página de releases](https://github.com/ethindp/prism/releases) e extraia na raiz do projeto. Ele registra o singleton `Prism`, que o jogo detecta sozinho.

## Áudio espacial

Árvores, água, arbustos e a Origem tocam sons contínuos na posição deles, e os passos das outras criaturas soam de onde elas estão. Você ouve sempre virado para o norte: esquerda é oeste e atrás é sul.

Com o [Nexus Resonance](https://github.com/undomick/godot-nexus-resonance) instalado, o som usa o HRTF binaural do Steam Audio, que deixa frente e trás claros **com fone de ouvido**. Sem ele, o jogo usa o áudio 3D do Godot (esquerda, direita e distância). O console avisa qual está em uso (`[audio] HRTF ...`).

## Atualizações

Ao abrir, o jogo procura a release mais nova em <https://github.com/gogabs/fawna/releases>. Se houver uma versão maior que a sua (`application/config/version` no `project.godot`), aparece a tela **Atualização disponível**, com fala e navegação por teclado:

- **Baixar e instalar:** baixa o zip do seu sistema, confere o tamanho e o SHA-256, fecha o jogo, troca os arquivos e abre de novo, já na versão nova. Esc cancela o download e R repete o progresso.
- **Ouvir novidades:** lê as notas da versão.
- **Pular:** vai para o menu principal.

Sem internet, ou sem versão nova, o jogo vai direto para o menu. Rodando pelo editor do Godot a verificação é pulada (use `--testar-atualizador` para ver a tela). `--sem-atualizar` pula a verificação. Se a pasta do jogo não aceitar escrita (ex.: dentro de Arquivos de Programas), o botão abre a página da versão para baixar à mão. O registro da troca de arquivos no Windows fica em `%TEMP%\fawna-atualizacao.log`.

### Publicar uma versão

O workflow `.github/workflows/publicar.yml` exporta o jogo para Windows e Linux (com as extensões de fala e áudio 3D) e cria a release com `fawna-<versão>-windows.zip` e `fawna-<versão>-linux.zip`. Para rodar:

- No GitHub, **Actions > Publicar versão > Run workflow**, informando a versão (ex.: `0.2.0`) e, se quiser, as novidades; ou
- `git tag v0.2.0 && git push origin v0.2.0`.

O workflow escreve a versão no `project.godot` exportado, então não precisa editar o arquivo à mão. Só entram na versão os sons que estão no repositório.

## Estrutura

```
autoload/   Speech (fala) e Net (modo de rede e conexão)
shared/     Código que roda igual no servidor e no cliente (mundo, recursos, trilhas, pássaros)
server/     Estado autoritativo do mundo e salvamento (só no servidor)
client/     Narrador, Caminheiro, menu flutuante, áudio espacial, sons, tema dos menus e atualizador
tools/      Scripts para baixar as extensões nativas
scenes/     Atualizador (primeira tela), menu (main) e jogo (game), que carrega as chamadas de rede
tests/      Testes automáticos
```

O servidor é autoritativo: os clientes só enviam intenções, como andar, e o servidor valida e avisa todos. O mundo vem de uma semente, então o servidor só precisa guardar o que os jogadores mudaram.

## Pássaros

Os primeiros seres vivos além das criaturas. Cada pássaro é uma entidade com posição própria, simulada no servidor (`shared/aviary.gd`): voa entre árvores e arbustos, canta só quando está pousado e foge de quem chega perto demais. Vivem em grupos: o sabiá-da-névoa e a coruja-do-breu andam sozinhos no bosque, o corvo-cinza em bandos pequenos no alto das árvores, o gavião-peneira sozinho nas árvores da pradaria, a rolinha-do-junco em casal e o periquito-do-brejo em bando perto da lagoa, e a carriça-do-cardo em bandos de 4 a 7 nos arbustos. Só existem perto de alguém, e cada jogador só recebe o que acontece até uns 48 m dele. No cliente (`scenes/birds.gd`), os cantos e as asas tocam em 3D com HRTF, numa altura de verdade (no alto da árvore, no arbusto, subindo no voo).

Os cantos são gerados por código (`client/bird_songs.gd`), discretos e meio inumanos. Gravações em `assets/sounds/passaros/` entram no lugar deles: `<espécie>_<voz>_<frase>` para os cantos (cada pássaro nasce com uma das vozes da espécie), `<espécie>_alarme` para o susto e `asas_<n>` para o voo. Uma voz sem arquivos usa os cantos gerados. `tools/comparar_passaros/` tem a página usada para escolher os sons. `tests/test_birds.gd -- --exportar=PASTA` salva os cantos gerados em .wav para ouvir.

## Testes

```sh
godot --headless --path . --script res://tests/test_world.gd
godot --headless --path . --script res://tests/test_updater.gd
godot --headless --path . --script res://tests/test_birds.gd
godot --headless --path . --script res://tests/test_harvest.gd
```

Caminheiro (precisa rodar como cena):

```sh
godot --headless --path . res://tests/test_caminheiro.tscn
```

Teste de rede com um servidor e dois clientes, todos sem tela:

```sh
godot --headless --path . -- --server --seed=42 &
godot --headless --path . -- --join=127.0.0.1 --name=Lua --auto=N,L,ARREDORES,QUEM,SAIR
```
