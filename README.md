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

- **Entrar no mundo como [nome]:** entra no servidor padrão (versão de testes: `26.127.36.156`, pela VPN). Sem nome definido nas Opções, não entra.
- **Hospedar um jogo privado:** sobe o servidor aqui, em qualquer endereço na porta UDP 7350, e põe você no mundo. Outros computadores da rede local o encontram por broadcast UDP na porta 7355 (libere no firewall).
- **Entrar em um jogo privado:** procura jogos na rede local e lista o que achar, com a opção de digitar o IP.
- **Opções:** muda seu nome (campo que mostra "Nome: valor" e só abre para digitar ao confirmar), o VSync, desliga os gráficos dentro do jogo (gasta bem menos processador; a janela fica parada) e escolhe a orientação das setas nos menus. Fica salvo em `user://config.cfg`. O servidor é sempre o padrão (7350).
- **Navegação:** só pelas setas, sem Tab. Horizontal (padrão): ← / → escolhem, ↑ confirma, ↓ volta. Vertical: ↑ / ↓ escolhem, → confirma, ← volta. Vale para o menu principal, as Opções, o menu flutuante e o Caminheiro.
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

Opções: `--server`, `--host`, `--debug` (liga o menu de depuração, veja abaixo), `--join=ENDEREÇO`, `--port=N`, `--name=NOME`, `--seed=N` e `--auto=N,L,ARREDORES,RADAR,SAIR` (comandos automáticos, usados nos testes).

### Depuração (só para testes)

O menu das setas ganha **Depuração** quando o servidor a liga: num servidor dedicado de testes com `--debug` (use outra porta que a do servidor principal, ex. `--server --debug --port=7351`; qualquer jogador que entrar nele usa) e em jogo hospedado pelo menu ou com `--host` (só quem hospeda usa, mesmo com convidados). Sem isso o menu não aparece e o servidor recusa os pedidos. Tem: dar pacotes de recursos (materiais de obra, raros, frutas, ferramentas ou tudo), esvaziar a bolsa, limite de carga alto (1000, sem sobrecarga), hora do dia (momentos como noite, coro do amanhecer ou meio-dia; o mundo vai sempre para a frente), estação (começo de cada uma), teleporte (40 casas para cada lado, miolo da faixa do anel ou longe dela, povoados e fogueiras), Calado (chamar atrás de você, dispensar, ligar/desligar as aparições sozinhas) e a posição atual. Comando de teste: `--auto=DBG_ação_argumento`.

## Controles

| Ação | Tecla |
| --- | --- |
| Andar para frente / para trás | W / S |
| Passo para o lado | A / D |
| Girar 45° para a esquerda / direita | Q / E |
| Menu flutuante (Caminheiro, Bolsa, Equipamento) | setas (orientação em Opções): ← / → escolhem, ↑ confirma, ↓ volta; no modo Vertical, ↑ / ↓ escolhem, → confirma, ← volta |
| Para onde estou olhando | F |
| Coletar | Espaço |
| Golpear com o machado (empunhado) | J |
| Ajuda (lista de comandos) | H |
| Radar: alvo do Caminheiro com a distância, o recurso mais próximo de cada tipo e as construções, num raio de 24 m | Tab |
| Com o Calado por perto: a respiração dele soa sozinha (some quando você fica de frente para ele) | virar (Q/E) |
| Onde estou; apertando de novo, o momento do dia, o anel e a estação (circular; o mundo anoitece e amanhece, e o Calado só ronda de noite) | C |
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
região do centro do mundo é onde nasce quem entra pela primeira vez. As trilhas são a base para o
Caminheiro e para os caminhos dos NPCs. As falas dizem onde as coisas
estão em relação a você: "árvore, à frente e à direita, 3 metros".

## Menu das setas e o Caminheiro

As setas não movem a criatura: elas operam um menu flutuante, sempre ativo.
← e → passam pelas opções, ↑ confirma e ↓ volta (em Opções dá para trocar para Vertical: ↑ e ↓ passam, → confirma e ← volta). As opções são o
**Caminheiro**, a **Bolsa** e o **Equipamento**.

O Caminheiro tem três submenus: **Locais** (os povoados com nome),
**Construções** (só as da região em que você está) e **Recursos** (Bambu, Lenha,
Pedras, Argila, Frutas), que acende o cristal rumo ao coletável mais próximo
daquele tipo, até uns 100 m em linha reta. Ao chegar, a fala diz onde ele
está: "Você chegou às pedras, atrás e à direita, 2 metros."

### Povoados

Um marco e uma fogueira prontos na mesma região fazem dela um povoado. Com
os dois prontos, Espaço no marco abre duas listas no menu das setas: primeiro
6 substantivos, depois 6 adjetivos (já concordando com o substantivo), sorteados
para aquele marco de listas maiores (`shared/settlement_names.gd`). A
combinação vira o nome do povoado ("Clareira Esquecida"), e só então ele
aparece em Locais. Seta para baixo na primeira lista desiste sem nomear.

Ao passar de uma região para outra soa um sopro grave e baixinho, sem fala
(gerado por código; um arquivo `assets/sounds/world/regiao.ogg` o substitui).

### Bolsa e Equipamento

A **Bolsa** lista o que a criatura carrega, agrupado: "Argila, 2". Lenha e
pedra têm tamanhos (grande, média, pequena), guardados como itens separados
(`pedra_grande`, `lenha_pequena`...) e falados juntos, só com os tamanhos que
a criatura tem: "Pedra, 3 grandes, 1 pequena". Itens sem
ação só repetem o nome. Alguns itens têm ação: o **machado** (toda criatura
chega ao mundo com um) tem **Empunhar**, que o tira da bolsa e o põe nas mãos.
O **Equipamento** mostra o que está nas mãos ("mãos livres" se nada), com o
botão **Guardar**, que devolve o item à bolsa. Com o machado empunhado, **J**
golpeia.

#### Carga e itens no chão

A criatura aguenta uma **carga** limitada (`Bag.CAPACITY`, 24), e cada item
pesa o seu tanto (`Bag.WEIGHTS`): fruta e lenha pequena 1, lenha média, bambu e
argila 2, pedra média 3, pedra grande 6, machado 3. Contam a bolsa e o que está
nas mãos. Dá para levar uma fogueira inteira (23), mas um marco (25) exige mais
de uma viagem, e quem sai carregado de pedras grandes só traz quatro. Para
deixar mais fácil ou difícil, mude só essas duas tabelas.

No fim da Bolsa há a linha "Carga, 18 de 24". Cada item abre **Jogar 1** e
**Jogar tudo** (e Empunhar, nas armas); lenha e pedra abrem antes a lista de
tamanhos. O que se joga cai na casa da criatura e vira um **monte no chão**, que
qualquer criatura pode pegar com **Espaço** (leva o que couber, do mais pesado
ao mais leve). Ao coletar com a carga quase cheia, o que não cabe também fica no
chão ("Carga no limite: 1 pedra grande ficou no chão") e o recurso é gasto; com
a carga lotada, a coleta é recusada e o recurso fica. Os montes não somem, ficam
salvos no `mundo.json` (`ground`), soam com um tique baixinho em 3D (até uns 13
m), aparecem no Tab ("itens no chão, à esquerda, 3 metros"), são anunciados ao
pisar neles e o Caminheiro leva até o mais próximo em **Itens no chão**.
Regras em `shared/bag.gd` e `shared/ground.gd`; testes em `tests/test_ground.gd`.

Quem decide é o servidor: o cliente pede para empunhar ou guardar, e o
servidor confere, muda a bolsa e as mãos e responde. A bolsa e o que está nas
mãos ficam salvos no mundo, pelo nome da criatura, e sobrevivem a reconexões.

O Caminheiro é um pequeno cristal que brilha azul na direção que o coração
manda: ele rastreia um lugar do mapa. Ao acender, traça a rota pelas
trilhas e pontes (`shared/wayfinder.gd`); se você estiver fora de uma trilha,
o primeiro trecho é o caminho mais rápido até a trilha mais próxima. Cada
curva da rota é um beacon. O coração (um tambor bem abafado) bate a 70 batidas
por minuto vindo da direção a seguir, que aponta um pouco à frente na rota e
só gira aos poucos, como um carro fazendo a curva: nunca pula, nem ao trocar
de beacon. Ao chegar ao destino, o cristal se apaga. Se você se afastar muito da rota, ela é traçada de
novo; "Apagar o cristal" aparece no menu enquanto ele está aceso. Ao escolher
um destino, o foco do menu fica onde está; escolher de novo o destino aceso
apaga o cristal.

## Como se joga (por enquanto)

1. Procure os recursos de ouvido e aperte **Espaço** perto deles para pôr na bolsa. O bambu e as frutas têm um som baixinho e próprio, em 3D:
   - **Touceira de bambu** (no bambuzal, mais cheio na orla dele, e em moitas na beira de lagoas, riachos e charcos do brejo): os colmos batem e rangem ao vento. Não se recolhe com a mão: com o machado empunhado, golpeie com **J** (de 3 a 5 golpes, conforme a touceira). No último golpe ela cai, e aí o Espaço recolhe 3 bambus. Golpes deixados pela metade se perdem depois de 3 minutos. **O bambuzal é uma parede**: fora das trilhas todas as casas são touceiras, e ao esbarrar o jogo avisa "Bambuzal fechado" e bate os colmos. Só se passa pelas trilhas ou abrindo caminho: bambu derrubado ou recolhido deixa passar. No bambuzal o caminho aberto fica para sempre; na beira da água o bambu rebrota em 15 minutos, mas espera se houver alguém em cima.
   - **Árvore** (bosque fechado): derrubada a machadadas (J), abre passagem para sempre; dá 2 madeiras (para as construções grandes que virão) e 2 lenhas grandes (para o fogo), itens separados. Os últimos golpes fazem o tronco ranger, e a queda se ouve de longe. Trocar de volta para "tudo lenha" é uma linha em `Harvest.SOURCES`.
   - **Arbusto com gravetos** (na orla da mata, onde ela encosta em campo aberto, clareiras incluídas; longe dali só um ou outro): quase todo arbusto dá gravetos para lenha (2 lenhas, cada uma média ou pequena; lenha grande só virá das árvores). Não tem som próprio: soa como os outros arbustos.
   - **Argila**, só na beira da água (margens das lagoas e dos riachos). Não tem som próprio: a água ao lado guia até ela. Dá 1 argila.
   - **Pedras** soltas, pelo mundo todo e bem mais comuns na beira dos riachos e lagoas. Dão 3 pedras, cada uma grande, média ou pequena (1/3 de chance cada); na beira da água saem mais pequenas (60% pequenas, 25% médias, 15% grandes). Não têm som próprio.
   - **Arbusto com frutas**, raro (uns poucos por região): em vez de gravetos, dá 2 frutas. Farfalha baixinho, com gotinhas.

   O que é recolhido some (sem som e sem fala no Tab; o arbusto fica, vazio, e o Tab o chama só de "arbusto") e rebrota com o tempo: gravetos em 5 minutos, argila em 8, pedras em 10, bambu em 15 e frutas em 30. O mundo é um só, então o que alguém colheu some para todos. As regras ficam em `shared/harvest.gd`.
2. Quem entra pela primeira vez nasce no cruzamento de trilhas do centro do mundo. Os minigames de profissão e a horta comunitária saíram para serem refeitos com outra roupagem.

O servidor salva o mundo em `user://mundo.json` (no Windows, `%APPDATA%\Godot\app_userdata\Fawna`). Use `--novo-mundo` para recomeçar ou `--mundo=caminho` para outro arquivo.

## Fala e leitores de tela

Os menus usam nós nativos do Godot, que o leitor de tela lê sozinho. Os anúncios do jogo passam pelo autoload `Speech`:

1. Se o [Prism](https://github.com/ethindp/prism) estiver instalado, a fala vai para o leitor de tela da pessoa (NVDA, JAWS, VoiceOver, Orca...) ou para um motor de voz.
2. Sem o Prism, o jogo usa a voz embutida do Godot.
3. Toda fala também é impressa no console com o prefixo `[fala]`.

Para instalar o Prism, baixe `prismatoid-gdextension` na [página de releases](https://github.com/ethindp/prism/releases) e extraia na raiz do projeto. Ele registra o singleton `Prism`, que o jogo detecta sozinho.

## Áudio espacial

Árvores, água, e arbustos tocam sons contínuos na posição deles, e os passos das outras criaturas soam de onde elas estão. Você ouve sempre virado para o norte: esquerda é oeste e atrás é sul.

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

## Senha do personagem

Cada nome tem uma senha, definida em **Opções** (mínimo de 4 caracteres) e guardada em `user://config.cfg` no PC de cada jogador. Na primeira vez que um nome entra no servidor, a senha enviada fica registrada (o save do mundo guarda só um hash com sal, em `credentials`); depois só entra quem souber a senha, e o mesmo personagem não entra duas vezes. Os personagens que já existiam no mundo não têm senha: o primeiro a entrar com o nome define a senha. Para resetar uma senha, apague a entrada do nome em `credentials` no `mundo.json` com o servidor parado. A senha viaja sem criptografia (como o resto do tráfego do jogo); serve para ninguém usar o personagem do colega, não para proteger algo sensível. Linha de comando: `--senha=...` (o padrão em testes é `teste`).

## Testes

```sh
godot --headless --path . --script res://tests/test_world.gd
godot --headless --path . --script res://tests/test_updater.gd
godot --headless --path . --script res://tests/test_birds.gd
godot --headless --path . --script res://tests/test_credentials.gd
godot --headless --path . --script res://tests/test_harvest.gd
godot --headless --path . --script res://tests/test_dia_noite.gd
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
