# Fawna

Jogo cooperativo e acessível (pensado primeiro para pessoas cegas) em que você é uma criaturinha híbrida ajudando a construir uma comunidade sustentável num mundo solarpunk. Todos jogam num único mundo compartilhado, que é gerado proceduralmente e cresce aos poucos, sem que ninguém destrua o que outra pessoa construiu.

Documento de design: <https://claude.ai/artifact/YTAHWweYCcywSAJtDc1GMh>

## Como rodar

O projeto usa **Godot 4.6 ou mais novo** e **GDScript**.

1. Instale as extensões nativas (fala e áudio 3D), que não ficam no repositório por serem grandes:
   - Windows (PowerShell): `./tools/instalar_extensoes.ps1`
   - Linux/macOS: `sh tools/instalar_extensoes.sh`
2. Abra a pasta no editor do Godot e aperte F5. Se for rodar só pela linha de comando, rode antes `godot --headless --path . --import` uma vez.

O jogo funciona sem as extensões, com a voz e o áudio 3D do próprio Godot, mas fica bem melhor com elas. No menu, digite seu nome e escolha:

- **Hospedar o mundo:** o seu jogo vira o servidor e você joga nele ao mesmo tempo.
- **Entrar no mundo:** conecta a um endereço (`ip` ou `ip:porta`). A porta padrão é 7350.

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
| Andar | Setas |
| Ouvir os arredores | Tab |
| Onde estou | C |
| Quem está no mundo | P |
| Repetir a última fala | R |

## Fala e leitores de tela

Os menus usam nós nativos do Godot, que o leitor de tela lê sozinho. Os anúncios do jogo passam pelo autoload `Speech`:

1. Se o [Prism](https://github.com/ethindp/prism) estiver instalado, a fala vai para o leitor de tela da pessoa (NVDA, JAWS, VoiceOver, Orca...) ou para um motor de voz.
2. Sem o Prism, o jogo usa a voz embutida do Godot.
3. Toda fala também é impressa no console com o prefixo `[fala]`.

Para instalar o Prism, baixe `prismatoid-gdextension` na [página de releases](https://github.com/ethindp/prism/releases) e extraia na raiz do projeto. Ele registra o singleton `Prism`, que o jogo detecta sozinho.

## Áudio espacial

Árvores, água, arbustos e a vila tocam sons contínuos na posição deles, e os passos das outras criaturas soam de onde elas estão. Você ouve sempre virado para o norte: esquerda é oeste e atrás é sul.

Com o [Nexus Resonance](https://github.com/undomick/godot-nexus-resonance) instalado, o som usa o HRTF binaural do Steam Audio, que deixa frente e trás claros **com fone de ouvido**. Sem ele, o jogo usa o áudio 3D do Godot (esquerda, direita e distância). O console avisa qual está em uso (`[audio] HRTF ...`).

## Estrutura

```
autoload/   Speech (fala) e Net (modo de rede e conexão)
shared/     Código que roda igual no servidor e no cliente (geração do mundo)
server/     Estado autoritativo do mundo (só no servidor)
client/     Narrador, áudio espacial, sons provisórios e visual de depuração
tools/      Scripts para baixar as extensões nativas
scenes/     Menu (main) e jogo (game), que carrega as chamadas de rede
tests/      Testes automáticos
```

O servidor é autoritativo: os clientes só enviam intenções, como andar, e o servidor valida e avisa todos. O mundo vem de uma semente, então o servidor só precisa guardar o que os jogadores mudaram.

## Testes

```sh
godot --headless --path . --script res://tests/test_world.gd
```

Teste de rede com um servidor e dois clientes, todos sem tela:

```sh
godot --headless --path . -- --server --seed=42 &
godot --headless --path . -- --join=127.0.0.1 --name=Lua --auto=N,L,ARREDORES,QUEM,SAIR
```
