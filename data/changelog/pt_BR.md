# Registro de alterações

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). Versões: [SemVer](https://semver.org/lang/pt-BR/).

## [Unreleased]

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
