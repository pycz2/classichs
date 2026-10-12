# Registro de alterações

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). Versões: [SemVer](https://semver.org/lang/pt-BR/).

## [Unreleased]

## [0.24.1] - 2026-10-12

### Alterado
- Os decks básicos saíram das listas de decks: cada classe tem um deck clássico. Um deck básico só aparece para uma classe sem deck clássico (nenhuma agora). Decks básicos não alterados saem uma vez dos decks salvos; os alterados ficam.

## [0.24.0] - 2026-10-12

### Adicionado
- Configurações → Conjunto de músicas: gerada ou livre (CC0) — músicas de taverna medieval de RandomMind: “Minstrel Dance” no menu, “The Old Tower Inn”, “King's Feast” e “The Bard's Tale” na partida. Os sons continuam os gerados.

## [0.23.3] - 2026-10-12

### Alterado
- O mulligan como no original: as cartas escolhidas voam para o deck, as novas ocupam os lugares delas e ficam na sua frente (“Esperando o oponente…”); quando o oponente escolheu, a Moeda aparece ao lado para o segundo jogador, depois todas as cartas descem para a mão na mesma ordem, e só então a carta do primeiro turno é comprada. A mão sob a tela de mulligan fica oculta.
- O botão do rastreador de deck fica sob o botão do menu e não cobre mais os cristais de mana do oponente.

## [0.23.2] - 2026-10-12

### Alterado
- Uma carta com Combo jogável na mão brilha em amarelo em vez de verde quando uma carta já foi jogada neste turno (o Combo vai funcionar).
- A Moeda sempre chega com a própria animação — gira com luz dourada e vai para a mão —, também quando o oponente terminou o mulligan depois, e para os dois jogadores.

## [0.23.1] - 2026-10-12

### Corrigido
- O botão que silencia o oponente mostra o estado: “Silenciar”, e “Ativar som” enquanto o oponente está silenciado.

## [0.23.0] - 2026-10-12

### Alterado
- Mulligan: depois de “Confirmar”, as cartas novas chegam à mão na hora, sem esperar o oponente, e ocupam o lugar das trocadas — a mão mantém a ordem da tela de mulligan; depois “Esperando o oponente…”. No online tudo continua sincronizado: o embaralhamento do mulligan usa o fluxo aleatório próprio de cada jogador.
- O cronômetro do mulligan online não tem pavio: nos últimos 10 segundos aparecem números vermelhos sob “Confirmar”.
- O que o oponente aponta não apaga mais o seu brilho: o verde ou o amarelo fica, com um leve anel vermelho por fora.
- Uma carta queimada por mão cheia queima só com o shader, sem os triângulos que sobem.

## [0.22.0] - 2026-10-12

### Adicionado
- Uma fila de ordens: a próxima jogada pode ser dada sem esperar a animação da anterior — jogar uma carta, atacar, usar o poder heroico, terminar o turno. As ordens esperam numa fila (marcadas em amarelo) e são cumpridas uma por uma depois das animações, em ordem; se uma ordem é possível é verificado depois das que já esperam. Se uma ordem fica impossível (o turno acabou), a fila é cancelada com um aviso. O tutorial não tem fila.

### Alterado
- O pavio do turno queima sem a linha pontilhada de cinzas atrás.

## [0.21.1] - 2026-10-12

### Alterado
- Jogo online: tudo o que o oponente aponta brilha em vermelho — lacaios, heróis, poderes heroicos, armas, segredos e a carta erguida na mão dele (antes só os lacaios, em branco).

## [0.21.0] - 2026-10-12

### Adicionado
- Regras da Arena: antes dos heróis, o anfitrião escolhe para os dois “Um deck para toda a Arena” ou “Um deck novo a cada partida”; o segundo tem a opção “Os jogadores podem manter o deck em vez de escolher de novo”. Com ela ligada, depois de cada partida cada um escolhe “Montar um deck novo” ou “Manter meu deck”, e o oponente vê que o jogador está decidindo. O convidado espera a escolha e vê as regras; o placar fica visível durante uma nova seleção.

### Alterado
- Arena: cartas lendárias aparecem o dobro (2 % numa escolha normal, 8 % nas escolhas 1, 10, 20 e 30), épicas uma vez e meia mais (7,5 % e 27 %).

## [0.20.1] - 2026-10-12

### Alterado
- As imagens do resultado foram comprimidas: o download volta a cerca de 61 MB (64 MB na 0.20.0).

## [0.20.0] - 2026-10-12

### Adicionado
- A Arena com um amigo online: Jogo Online → Arena. Cada um pega um de três heróis e monta 30 cartas como na Arena de 2014: três cartas de uma raridade por escolha (básicas e comuns contam como uma), rara ou melhor nas escolhas 1, 10, 20 e 30, cartas de classe uma vez e meia mais frequentes, sem limite de cópias. A lista do deck à direita, a curva de mana embaixo à esquerda, o progresso do oponente em cima à direita (herói escolhido ou não, cartas, pronto; nunca o herói nem as cartas). Quando os dois tocam em “Pronto”, começa uma série até três vitórias; depois de cada partida, o saguão com o placar; dá para desistir da Arena ou sair para o menu a qualquer momento.
- O resultado de uma partida do seu lado — Vitória!, Derrota ou Empate — sobre uma imagem semitransparente (online aparecia “Jogador N vence”).

### Verificado
- Empate: um Fogo do Inferno que mata os dois heróis dá empate, e os dois heróis se despedaçam.

## [0.19.5] - 2026-10-12

### Corrigido
- Site: a seção de código aberto mostrava “{tests}” no lugar do número de testes.

## [0.19.4] - 2026-10-12

### Adicionado
- Um link para o site no Telegram, WhatsApp, Discord, Slack e outros mensageiros mostra uma prévia com a captura principal do jogo (uma partida), o título e uma descrição.

## [0.19.3] - 2026-10-12

### Adicionado
- Site: a versão do jogo e um bloco “Novidades” (as últimas entradas do registro no idioma da página), uma seção “Na partida”, perguntas e respostas (requisitos, celulares, onde ficam os decks, jogar offline, instalar como aplicativo, o que o jogo online envia, como relatar um erro), uma seção de código aberto; o link do registro abre o idioma da página; no celular a página não rola mais para o lado.

## [0.19.2] - 2026-10-12

### Alterado
- O site e o README agora batem com o jogo: treino com escolha de deck e herói do bot, dez decks Classic famosos, o repetidor do jogo online, ferramentas de depuração nas Configurações, emotes com as palavras dos heróis, conjuntos de artes e versos; os passos online usam os nomes dos botões do jogo; afirmações antigas foram removidas (nenhum servidor, toda a arte desenhada por código).

## [0.19.1] - 2026-10-12

### Alterado
- Site: novas capturas (histórico por turnos, rastreador de deck, lições antes das missões, ferramentas de depuração; a página russa mostra capturas em russo), textos atualizados e tamanho do download (cerca de 61 MB). No celular, um toque amplia uma carta do leque e dois toques a viram.

## [0.19.0] - 2026-10-12

### Adicionado
- Na primeira execução o jogo pede para escolher o idioma; o do sistema fica destacado.

## [0.18.5] - 2026-10-12

### Alterado
- Dano aleatório em vários alvos (Mísseis Arcanos, Ira Vingativa, Bombardeiro Louco, Rajada de Flechas, Relâmpago Bifurcado etc.) voa um projétil por vez; a vida do alvo cai a cada acerto.

## [0.18.4] - 2026-10-12

### Adicionado
- Esquivo: o lacaio fica envolto numa névoa dourada cintilante, e a palavra tem sua janelinha (feitiços e poderes heroicos não podem escolhê-lo como alvo).

## [0.18.3] - 2026-10-12

### Adicionado
- Cartas queimadas (mão cheia) e dano de fadiga aparecem no histórico à esquerda: um quadro próprio com imagem e explicação ao passar o mouse.

### Corrigido
- Tutorial: o Mestre Cho não pode ser atacado enquanto tiver lacaios.

## [0.18.2] - 2026-10-12

### Alterado
- A síntese de voz foi removida: o jogo não lê mais nomes e emotes em voz alta; as opções Voz e Fala saíram das configurações. As falas dos heróis aparecem como texto em balões com a ponta voltada para o herói.

### Corrigido
- Uma caixa marcada perdia o fundo sob o mouse.

## [0.18.1] - 2026-10-12

### Adicionado
- Editor de cena: zonas de Segredos e Arma, escolha de quem joga primeiro e fichas na lista de cartas.

## [0.18.0] - 2026-10-12

### Alterado
- As ferramentas de depuração foram para as configurações e viraram uma tela com abas: "Cena" (montar uma cena com o mouse: heróis, mana, dano, armadura, mão, mesa, deck; o JSON ao lado; o modo com botões de opção), "Teste de interações" (cenários prontos para cada uma das 534 cartas, 1108 ao todo: escolha carta e cenário e ele roda numa partida real com todos os efeitos e sons), "Teste de cartas" e "Teste de efeitos".

## [0.17.1] - 2026-10-12

### Adicionado
- Na derrota, o retrato do herói explode em estilhaços.
- Os símbolos de raio e veneno ficam parados e pulsam com um som leve quando o efeito dispara.

### Corrigido
- Tutorial: "Próxima missão" abre as explicações numa tela própria; a tela de recompensa não bloqueia mais.

## [0.17.0] - 2026-10-12

### Adicionado
- O histórico à esquerda é separado por turnos ("Turno N" na cor do jogador); ao passar o mouse sobre uma ação vê-se o que ela fez e a quem: dano, cura, bônus, congelamento, silêncio, mortes, evocações, armas equipadas e os gritos de guerra e últimos suspiros que disparou. As cartas ocultas do oponente continuam ocultas.
- O rastreador de deck tem seu próprio botão ao lado do menu: "Seu deck" com imagens, ×2, cartas esgotadas escurecidas e a chance de comprar cada carta; "Jogado pelo oponente", uma lista que cresce com ×2.

## [0.16.2] - 2026-10-12

### Corrigido
- Tutorial: após uma vitória, "Próxima missão" abria as explicações por baixo da tela de recompensa e a tela travava.

## [0.16.1] - 2026-10-12

### Adicionado
- Abaixo do botão "Encerrar turno": o tempo da partida e, online, o tempo restante do turno.
- Tudo na mesa se ilumina sob o mouse; uma arma vira quando não é o turno do seu herói.
- Lacaios e heróis dizem suas falas (ao entrar, atacar, morrer, emotes, início da partida, desistência) quando há gravação; os emotes dos heróis com suas próprias palavras.

### Alterado
- O pavio do cronômetro é um cordão trançado com uma brasa, faíscas e fumaça.
- Uma carta queimada se consome a partir das bordas com uma borda incandescente.
- Golpe no herói: número de dano maior; mais de 5 de dano treme mais forte com um som pesado.
- Um herói que pode atacar brilha mais.

## [0.16.0] - 2026-10-11

### Adicionado
- Menu principal: Jogar abre um submenu com jogo online, treino e tutorial.
- Treino em etapas: escolha um deck numa lista com retratos dos heróis (ou vá aos decks), depois o oponente numa grade 3×3, depois Jogar.
- Jogo online em etapas: nome, deck, Criar jogo ou Entrar; os códigos têm um botão Copiar ao lado.
- Tutorial: missões com os retratos dos chefes; antes de cada missão, explicações ilustradas dos novos conceitos (partes da carta, combate, mana, feitiços, grito de guerra, provocar, investida, último suspiro, poder heroico, congelar, armas).
- Coleção e decks numa só tela: todas as cartas à esquerda com abas de classe, filtros de tipo, custo, raridade e busca; os decks à direita com copiar, exportar e excluir; um deck é editado no mesmo lugar.

### Corrigido
- Jogo online: um repetidor TURN para redes sem caminho direto; o convidado espera até 4 minutos pela resposta do anfitrião e renova os candidatos de conexão todo esse tempo (antes o navegador desistia em poucos segundos).

## [0.15.3] - 2026-10-11

### Adicionado
- A tela de carregamento mostra a versão do jogo.

## [0.15.2] - 2026-10-11

### Alterado
- Os emblemas de classe são simples e planos; a espada da gema de ataque é mais curta, aponta para cima à direita, com o cabo visível embaixo à esquerda; o raio sob o retrato tem metade do tamanho; o frasco de veneno é verde, menor e parado.
- Silêncio: fitas rosas brilhantes envolvem o retrato.
- Último Suspiro: a caveira cresce do lacaio e sobe.
- Um lacaio com grito de guerra primeiro ocupa seu lugar, e então a seta para o alvo sai dele; o clique direito ou levar a seta de volta à mão cancela, e a carta volta para a mão.

### Corrigido
- As faíscas de Dano Mágico às vezes paravam.

## [0.15.1] - 2026-10-11

### Alterado
- As gemas de mana, vida, ataque, armadura e durabilidade estão menores e lisas no centro para ler melhor os números; as marcas sob o retrato estão menores.

## [0.15.0] - 2026-10-11

### Adicionado
- Imagens de interface pintadas: cristal de mana, gota de vida, gema de ataque com espada, escudos de armadura e durabilidade, escudo de Provocar, caveira com ossos, frasco de veneno, raio, emblemas de classe, uma imagem para a fadiga.
- Lacaios venenosos (Naja Imperial, Assassina Paciente) têm um frasco de veneno.
- Uma janelinha de palavra-chave para Enfurecer.
- A carta de um lacaio silenciado mostra o texto riscado com uma cruz vermelha ao passar o mouse.
- A sobrecarga aparece na hora: cadeados laranja sobre os cristais para o próximo turno; um cristal bloqueado mostra um cadeado em vez de uma cruz.
- Uma carta criada por uma carta na mesa (Arquimago Antonidas, Ysera) voa dela para a mão.

### Alterado
- Os brilhos (jogável, selecionado, alvo) ficam sempre do lado de fora de todos os efeitos de uma carta.
- Fúria dos Ventos: rajadas numa órbita inclinada, por trás e pela frente da carta.
- Furtividade: uma névoa através da qual a imagem aparece de leve; Congelado: uma camada de geada e uma borda gelada.
- Os segredos no retrato do herói são redondos: roxos para o mago, verdes para o caçador, amarelos para o paladino.
- As gemas de raridade são redondas, com sombra e brilho.
- O dragão de um lacaio lendário cobre só a parte de cima do oval.

## [0.14.1] - 2026-10-11

### Alterado
- O dragão de um lacaio lendário na mesa se enrola em volta do oval do retrato.

### Corrigido
- No navegador, o primeiro Cmd/Ctrl+V não colava nada em vez do código copiado (código de um amigo, importar deck).
- Jogo online: o tempo com a aba oculta não interrompe mais a espera pela conexão.
- Uma carta na mão pode ser pega clicando abaixo da carta levantada, onde ela estava.
- As janelinhas de palavras-chave voltam a aparecer ao passar o mouse sobre uma carta na mão.

## [0.14.0] - 2026-10-11

### Adicionado
- 10 decks clássicos prontos no menu de decks: Control Warrior, Midrange Shaman, Midrange Druid, Control Priest, Miracle Rogue, Midrange Paladin, Handlock, Freeze Mage, Midrange Hunter, Zoolock. Jogadores com decks salvos os recebem uma vez.

## [0.13.0] - 2026-10-11

### Adicionado
- Mulligan: as cartas trocadas voam para o deck, as novas ocupam seus lugares, a moeda surge girando com luz dourada e depois a mão inteira desce. As cartas marcadas para troca têm um selo vermelho com uma cruz branca.
- Fadiga: uma carta escura com uma caveira e seu dano voa do deck vazio para o herói.
- Uma carta queimada (mão cheia) aparece e pega fogo.
- Passar o mouse sobre um deck também mostra quantas cartas esse jogador tem na mão.

### Alterado
- A mana que a carta sob o mouse gastaria pulsa claramente, se houver o suficiente.
- O brilho de cartas e botões jogáveis é mais estreito e mais forte na borda.

## [0.12.2] - 2026-10-11

### Alterado
- Cartas jogáveis, lacaios, o poder heroico e o botão "Encerrar turno" têm um brilho suave e pulsante em vez de um contorno.

## [0.12.1] - 2026-10-11

### Adicionado
- Passar o mouse sobre uma carta na mão faz piscar os cristais de mana que ela gastaria, se puder ser jogada.

## [0.12.0] - 2026-10-11

### Adicionado
- Efeitos na mesa: feitiços, gritos de guerra, últimos suspiros e efeitos de início e fim de turno lançam projéteis da origem para cada alvo. No impacto, cada lacaio e herói mostra o que aconteceu: uma explosão para dano, faíscas para cura, setas para bônus ou penalidade, um brilho para uma nova palavra-chave, gelo, um anel de silêncio, fumaça de transformação, um portal de evocação, uma caveira de último suspiro, um clarão de grito de guerra, um redemoinho ao mudar de controle, um escudo de armadura.
- Os números que mudam nas cartas crescem por um instante com sua gema.
- A raça da carta (Fera, Demônio, Dragão, Murloc, Mecanoide, Totem, Pirata, Morto-vivo) numa placa na parte de baixo da carta.
- Um lacaio imune brilha em branco com faíscas girando ao redor.

### Alterado
- O escudo de Provocar segue o contorno do retrato.
- "Seu turno" aparece depois dos efeitos de fim de turno.

## [0.11.0] - 2026-10-11

### Adicionado
- Seis versos de carta para escolher nas configurações: Clássico, Horda, Druida, Arcano, Ouro, Noite.
- Laboratório de efeitos na mesa de depuração: qualquer carta na mesa e na mão com suas janelinhas; palavras-chave, bônus, penalidades, auras, dano, silêncio, sono, mudanças de custo e brilhos podem ser ligados e desligados em qualquer um dos 8 idiomas.

### Alterado
- A mesa muda no momento do golpe: números, escudos e mortes aparecem quando o atacante toca o alvo ou o projétil do feitiço chega, não antes. Um lacaio que morre desaparece com seus últimos números.

### Corrigido
- Na versão web havia um retângulo branco no lugar do dragão acima do título do menu.
- As cartas da página do jogo são desenhadas pelo próprio jogo e ficam iguais às do jogo.

## [0.10.0] - 2026-10-11

### Adicionado
- Cada carta agora tem sua própria imagem gerada.
- O texto das cartas foi diagramado à mão para cada carta em cada idioma: as linhas, o tamanho da fonte e a posição. Uma verificação garante que nenhum texto passe da moldura nem invada as gemas; as linhas são equilibradas, os números ficam com sua palavra e as palavras-chave não são quebradas.
- Laboratório de cartas (na mesa de depuração): uma carta nos 8 idiomas ao mesmo tempo, com suas molduras e uma lista de problemas; tamanhos, posição e linhas podem ser alterados e salvos.
- Os lacaios mostram suas mudanças em janelinhas: bônus com a carta que os deu, auras, valores definidos, palavras-chave ganhas, Congelado, Silenciado. Janelinhas de palavras-chave também na coleção e na montagem de decks.
- Cartas lendárias: um friso dourado e reto com um dragão ao longo da borda superior da carta.
- A tela de carregamento com a aparência atual do menu.

### Alterado
- A espada atrás da gema de ataque sai pelo canto superior esquerdo, além da borda da carta, longe do texto.
- Mais contraste nos números das cartas, principalmente em valores aumentados e danificados.

### Corrigido
- O texto em francês de algumas cartas mostrava "|4(point,points)" em vez de "point" ou "points".
- Na página do jogo, a última letra do título não é mais cortada.

## [0.9.0] - 2026-10-12

### Adicionado
- Menu principal: um fundo de taverna gerado com zoom lento, faíscas voando, um título dourado vetorial com um dragão e um brilho que percorre o texto; os botões aparecem um por vez.
- Fundos gerados: a partida é jogada em um tabuleiro de pedra sobre uma mesa de taverna, a escolha de baralho e a coleção ficam em uma biblioteca de taverna, e as demais telas, em uma taverna escurecida.
- Fonte Alegreya para a interface (latino, cirílico, grego) e botões de madeira no estilo da taverna, com cantos arredondados e moldura dourada; campos de entrada arredondados, controles deslizantes dourados.
- Os textos das cartas sempre cabem na moldura: o tamanho da fonte é ajustado por medição para cada carta em cada idioma. Palavras-chave em negrito.
- Caixas com a explicação das palavras-chave ao lado da carta ampliada.
- Uma espada atrás da pedra de ataque, um pequeno dragão gerado nas cartas lendárias.
- O poder heroico vira após o uso; o botão "Finalizar turno" brilha em verde quando não há mais jogadas.
- Filtro de raridade na coleção e na montagem de baralhos.
- Listas de baralhos como no original: uma faixa com o retrato do herói atrás do nome do baralho, uma faixa com a arte da carta na lista de cartas do baralho, o custo em um cristal, o preenchimento do baralho como uma barra.
- O registro de alterações abre no idioma do jogo.
- O jogo pode ser instalado como aplicativo (PWA) e jogado offline após o primeiro carregamento.
- Na página do jogo, as capturas de tela estão em inglês.

### Corrigido
- Intenções repetidas ou frequentes demais do oponente não sobrecarregam mais a mesa; a carta pop-up do histórico não é recriada a cada movimento do mouse; a confirmação do mulligan cede ao cronômetro e à perda de conexão; uma carta arrastada permanece sobre a mesa.

## [0.8.1] - 2026-10-11

### Corrigido (após a revisão)
- No jogo online, o temporizador podia encerrar sozinho o novo turno enquanto a animação da jogada do oponente ainda terminava.
- O clique direito durante o arrasto de uma carta cancela o arrasto sem erros.
- As cartas da mão não são mais desenhadas por cima das configurações, do menu, do mulligan e da tela de fim de partida.
- Um lacaio devolvido à mão ou transformado muda no lugar, em vez de "morrer" com uma nova carta do baralho.

## [0.8.0] - 2026-10-11

### Adicionado
- Mesa como no original: lacaios ovais com pedra de ataque e gota de vida, escudo de pedra da Provocação, dragão dourado sobre os lendários, molduras de cartas com faixa de nome e pergaminho, retratos de heróis em arco com o brasão da classe.
- Efeitos animados na mesa: Fúria dos Ventos, Escudo Divino, Furtividade, Congelamento, sono, gatilhos, Último Suspiro, auras, Enfurecer, dano de feitiços, Silêncio.
- Arrastar cartas: a carta segue o cursor, os lacaios se afastam para abrir espaço de inserção, setas curvas para feitiços, ataques e poder heroico. Escolher com cliques também funciona.
- Animações: comprar carta do baralho, jogar carta (a carta do oponente vira no meio do caminho), voo de feitiços, ataque de lacaios e do herói, poder heroico, morte, retorno à mão, mulligan, revelação de segredo, banner "Seu turno", falas com o herói "falando". O bot espera o fim das animações.
- Mão em leque: a carta sob o cursor sobe e aumenta.
- Baralho junto ao herói: a espessura reflete o número de cartas, o número exato aparece ao passar o cursor.
- Menu de engrenagem no canto superior direito: histórico, deck tracker, configurações, desistir. Emoções com clique direito no seu herói, "Silenciar" no herói do oponente.
- Faixa de histórico à esquerda: imagens das cartas jogadas, a carta aparece ao passar o cursor, o histórico em texto abre com um clique.
- No jogo online dá para ver para onde o oponente está olhando: a carta levantada na mão dele, a seta vermelha dele, o lacaio destacado.
- Imagens das cartas: ilustrações geradas (Codex local), arte original (apenas para jogo local) e conjuntos próprios, qualquer pasta em `art/`; a escolha fica nas configurações. Onde não há imagem, usa-se arte desenhada, única para cada carta.
- Configuração da velocidade das animações: de normal até 4 vezes mais rápida.
- Baralho básico para cada herói na primeira execução.
- Ícones de classe na coleção, na escolha de herói e de oponente; os filtros de custo agora são cristais de mana.
- Página do jogo em 8 idiomas, com imagens das cartas, retratos de heróis, leque de cartas, faíscas e contadores.

### Alterado
- Música nova em estilo de taverna: alaúde e harpa dedilhados, flauta, pad, baixo, pandeiro e shaker, eco e reverberação. O menu tem uma valsa tranquila, e a partida tem três faixas diferentes de 60 a 90 segundos. Cada partida começa com uma faixa diferente da anterior, e quando a faixa termina toca a próxima.
- Cristais de mana no lugar do texto "Mana 3/5".

## [0.7.0] - 2026-10-11

### Adicionado
- Página do jogo no GitHub Pages: https://pycz2.github.io/classichs/ — cabeçalho animado, recursos, galeria de capturas de tela, em russo e inglês; o jogo pode ser iniciado direto na página.
- `README.md` com capturas de tela, recursos, compilação e estrutura do projeto.
- `tools/build_site.sh`: compila o site e publica na branch `gh-pages`.

### Alterado
- O exemplo na mesa de depuração agora é uma posição de vitrine: segredo, arma, Provocação, lacaios lendários, mão cheia.
- As falas em russo do chefe da primeira missão usam o nome oficial "Hogger".

### Corrigido
- Símbolos ausentes na fonte apareciam como quadrados: os ícones dos lacaios (Último Suspiro, gatilho, Silêncio) agora são vetoriais e a seta é ASCII. Um teste verifica que a fonte contém todos os símbolos da interface e das traduções.

## [0.6.0] - 2026-10-11

### Adicionado
- Interface em 8 idiomas: English, Русский, Deutsch, Français, Español, Português (Brasil), Italiano, Polski. O idioma padrão é o do sistema; a troca nas configurações é imediata, sem reiniciar.
- Tela de configurações (no menu e na partida): idioma, volume da música, dos sons e da voz, dublagem, tremor de tela, tela cheia, nome do jogador.
- Arte vetorial para cada carta, herói e poder heroico: um motivo conforme o nome, a raça, o tipo e a classe (fogo, gelo, yeti, ovelha, murloc, arma e outros).
- Sons dos eventos da mesa e duas melodias (menu e batalha); todos os sons são sintetizados, sem arquivos externos.
- Dublagem com a voz do sistema no idioma da interface: nomes de lacaios lendários e de novos heróis, emoções, falas dos chefes do tutorial.
- Registro de alterações: clicar na versão no canto do menu abre todo o histórico de alterações do jogo.
- Deck tracker na partida: o seu baralho, as cartas restantes com a chance de comprar cada uma em seguida, as cartas que o oponente jogou. Cada visão pode ser ocultada; a escolha é lembrada.
- Temporizador de turno no jogo online: 75 segundos, nos últimos 15 segundos o pavio queima; quando o tempo acaba, o turno termina sozinho.

### Alterado
- O histórico de turnos marca o início do turno pelo evento, não pelo texto; o painel de histórico não pula para baixo enquanto o jogador lê entradas antigas.
- Os motivos de dessincronização e o nome padrão do jogador agora são traduzidos.

### Corrigido
- O botão "Desistir" não virava "Menu" após o fim da partida.

### Corrigido (após a revisão)
- O histórico de turnos mostra os novos turnos depois de aberto.
- A troca de idioma na partida também muda os títulos do deck tracker e do histórico, o nome do bot e as janelas abertas.
- Textos longos de cartas não saem mais da moldura.

## [0.5.0] - 2026-10-11

### Adicionado
- Tutorial: seis missões com Jaina Proudmore, como no original — Hogger, Millhouse Manavento, Andarilho das Lendas Cho, Rei Mukla, Rosarães Guima, Illidan Tempesfúria.
- Dicas passo a passo, falas dos chefes, regras das primeiras missões (não dá para perder, não dá para encerrar o turno com mana ou ataque não gasto), o poder heroico é liberado na quinta missão.
- Cartas dos chefes do tutorial: Hogger ESMAGA!, Barril, Pisada, Vontade de Mukla, Transcendência, Chamas de Azzinoth, Estouro Flamejante e outras.
- Tela de recompensa após a vitória; o progresso do tutorial é salvo, e as missões concluídas podem ser jogadas de novo.

## [0.4.0] - 2026-10-11

### Adicionado
- Jogo online no navegador sem servidor próprio: WebRTC direto entre navegadores, STUN público do Google. O anfitrião cria um código de convite, o convidado responde com um código de resposta; os códigos podem ser enviados por qualquer mensageiro.
- Sincronização da partida: os dois lados verificam o estado do jogo após cada jogada; em caso de divergência, versão incorreta do jogo ou queda da conexão, aparece uma mensagem clara.
- Nome do jogador (visível ao oponente), 6 emoções e o botão "silenciar oponente".

### Corrigido (após a revisão)
- No jogo online, os dois jogadores escolhem o mulligan ao mesmo tempo.
- Conexão mais confiável entre redes diferentes: o jogo espera o navegador descobrir o endereço externo; há um tempo limite de conexão com dica.
- Mensagens claras: "o oponente saiu", "outra versão do jogo", "dados de cartas diferentes", "dessincronização".
- As emoções não podem ser enviadas mais de uma vez a cada 1,5 segundo; "silenciar" esconde imediatamente a emoção exibida.

## [0.3.0] - 2026-10-11

### Adicionado
- Coleção: todas as 382 cartas, páginas de 8 cartas, abas de classes, filtro de custo, busca, carta ampliada ao passar o cursor.
- Baralhos: quantidade ilimitada, criação, edição, cópia, exclusão; regras do Hearthstone (30 cartas, 2 cópias, 1 lendária, apenas da própria classe e neutras).
- Os baralhos são salvos no navegador e permanecem após reiniciar; um arquivo corrompido não se perde, é movido para `decks.bad.json`.
- Códigos de baralho do Hearthstone: exportação no formato Classic; importação de códigos nos formatos Classic, Standard e Wild, incluindo baralhos antigos de 2014–2016 com as cartas originais e texto copiado do cliente.
- Treino: escolha do próprio baralho; um baralho incompleto não pode ser iniciado.

### Corrigido (após a revisão)
- O erro de importação de código é mostrado na janela de importação.
- Um baralho com uma carta que deixou de existir abre e pode ser editado; o jogador é avisado se o arquivo de baralhos estava corrompido (a cópia é salva).
- São importados códigos de baralho com outros visuais de herói (Magni, Medivh etc.) e códigos de texto com título na primeira linha.
- O baralho é salvo após cada alteração, e não só pelo botão "Done".

## [0.2.0] - 2026-10-11

### Adicionado
- Menu principal, escolha de classe para o treino, baralhos básicos das nove classes.
- Mesa de jogo: heróis, poderes heroicos, armas, segredos, mesas, mãos, mana; mulligan, Escolha Um, escolha de Rastreamento, tela de fim de partida.
- Controle pelo mouse: carta → opção → lugar na mesa → alvo; ataque; poder heroico; dica com carta ampliada.
- Efeitos simples: números flutuantes de dano e cura, sombra do lacaio morto, tremor de tela em dano forte.
- Bot de treino: testa ações em uma cópia do jogo e escolhe a melhor.
- Histórico de turnos durante a partida: todos os turnos desde o início, sem limite de tamanho; as cartas compradas pelo oponente ficam ocultas.
- Mesa de depuração: cenário em JSON, busca de carta e adição à mão, à mesa ou ao baralho; jogo contra o bot ou pelos dois lados; botão "Posição → JSON".

### Corrigido (após a revisão)
- Dá para colocar um lacaio entre outros clicando no lacaio vizinho.
- O histórico não mostra ao oponente as cartas descartadas por Rastreamento.
- A mesa de depuração informa tipos de campo incorretos no cenário e não inicia uma partida quebrada.
- Desistir da partida exige confirmação.
- O bot pensa mais rápido em posições grandes.

### Corrigido
- O segredo conta como feitiço: Moreia de Mana, Arquimago Antônidas, Piromante Selvagem, Leiloeiro de Geringontzan, Professora Violeta e Viciada em Mana o enxergam; Contrafeitiço cancela o segredo.
- Insanidade Sombria: o lacaio roubado pode atacar mesmo que tenha atacado no turno anterior do dono.
- Rastreamento não descarta cartas que o jogador não viu.
- Mulligan: o resultado não depende da ordem em que os jogadores confirmaram a escolha (importante para o jogo online).
- Dá para desistir a qualquer momento, inclusive no turno do oponente e durante o mulligan.
- Os cenários preservam o custo das cartas na mão, o estado do herói e o contador de lacaios jogados; um erro no cenário gera uma mensagem, e não uma falha.
- Cria da Luz não depende da ordem das auras; Ocultar não remove a Furtividade própria do lacaio; Armadilha de Cobra não dispara com a mesa cheia.
- Uma ação inválida (por exemplo, vinda da rede) é rejeitada sem alterar o estado.

## [0.1.0] - 2026-10-11

### Adicionado
- Esqueleto do projeto em Godot 4.7 e executor de testes.
- Dados de 382 cartas colecionáveis do formato Classic (junho de 2014), tokens e cartas do tutorial em 14 idiomas.
- Motor: início da partida, mulligan, A Moeda, turno, mana, Sobrecarga, Fadiga, queima de cartas, descongelamento de Congelado.
- Motor: histórico completo da partida (`history`) — cada ação e todos os seus eventos desde o início da partida.
- Motor: jogar cartas, Grito de Guerra, Combo, Escolha Um, segredos, armas, ataques, Provocação, Furtividade, Fúria dos Ventos, poder heroico, lista de ações legais.
- Motor: cenários — montagem de qualquer posição a partir de JSON e salvamento da posição atual em JSON (base da mesa de depuração).
- Cartas: poderes heroicos das 9 classes, INFERNO!, Aguilhão Mental, Ruptura Mental, A Moeda.
- Cartas: Básicas neutras (43).
- Cartas: Classic COMUNS neutras (40).
- Cartas: Classic RARAS neutras (36).
- Cartas: Classic ÉPICAS neutras (11).
- Cartas: lendárias neutras, de recompensa e promocionais (27) e seus tokens: Bananas, cartas Sonho, Acorde Poderoso, invenções de Gelbin, Totem de Cura.
- Cartas: Druida (25) e variantes de Escolha Um.
- Cartas: Caçador (25), segredos do caçador, Rastreamento.
- Cartas: Mago (25), segredos do mago.
- Cartas: Paladino (25), segredos do paladino.
- Cartas: Sacerdote (25).
- Cartas: Ladino (25), Combo.
- Cartas: Xamã (25), Sobrecarga.
- Cartas: Bruxo (25), Lorde Jaraxxus.
- Cartas: Guerreiro (25). Todas as 382 cartas colecionáveis do formato Classic estão implementadas.
- Verificação de completude: toda carta com efeito tem um gancho; 1000 partidas aleatórias sem erros; o motor funciona na build web, o hash coincide com o nativo.
