# Registro delle modifiche

Formato: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Versioni: [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.23.0] - 2026-10-12

### Modificato
- Mulligan: dopo “Conferma” le carte nuove arrivano subito in mano, senza aspettare l'avversario, e prendono il posto di quelle sostituite — la mano mantiene l'ordine della schermata del mulligan; poi “In attesa dell'avversario…”. Online tutto resta sincronizzato: il mescolamento del mulligan usa il flusso casuale proprio di ogni giocatore.
- Il timer del mulligan online non ha la miccia: negli ultimi 10 secondi compaiono numeri rossi sotto “Conferma”.
- Ciò che indica l'avversario non spegne più il tuo bagliore: il verde o il giallo resta, con un leggero anello rosso all'esterno.
- Una carta bruciata per mano piena brucia solo con lo shader, senza i triangoli che salgono.

## [0.22.0] - 2026-10-12

### Aggiunto
- Una coda di ordini: la mossa successiva si può dare senza aspettare la fine dell'animazione precedente — giocare una carta, attaccare, usare il potere eroe, finire il turno. Gli ordini aspettano in coda (segnati in giallo) e vengono eseguiti uno alla volta dopo le animazioni, in ordine; se un ordine è possibile si controlla dopo quelli già in coda. Se un ordine diventa impossibile (il turno è finito), la coda viene annullata con un suggerimento. Il tutorial non ha la coda.

### Modificato
- La miccia del turno brucia senza la linea tratteggiata di cenere dietro.

## [0.21.1] - 2026-10-12

### Modificato
- Partita online: tutto ciò che l'avversario indica brilla di rosso — servitori, eroi, poteri eroe, armi, segreti e la carta sollevata nella sua mano (prima solo i servitori, in bianco).

## [0.21.0] - 2026-10-12

### Aggiunto
- Regole dell'Arena: prima degli eroi, l'host sceglie per entrambi “Un mazzo per tutta l'Arena” o “Un mazzo nuovo per ogni partita”; il secondo ha l'impostazione “I giocatori possono tenere il mazzo invece di sceglierne uno nuovo”. Se è attiva, dopo ogni partita ognuno sceglie “Costruire un mazzo nuovo” o “Tenere il mio mazzo”, e l'avversario vede che il giocatore sta decidendo. L'ospite aspetta la scelta e vede le regole; il punteggio resta visibile durante una nuova selezione.

### Modificato
- Arena: le carte leggendarie escono il doppio (2 % in una scelta normale, 8 % alle scelte 1, 10, 20 e 30), le epiche una volta e mezza di più (7,5 % e 27 %).

## [0.20.1] - 2026-10-12

### Modificato
- Le immagini del risultato sono compresse: il download torna a circa 61 MB (64 MB nella 0.20.0).

## [0.20.0] - 2026-10-12

### Aggiunto
- L'Arena con un amico online: Partita online → Arena. Ognuno prende uno di tre eroi e costruisce 30 carte come nell'Arena del 2014: tre carte di una rarità per scelta (base e comuni contano come una), rara o meglio alle scelte 1, 10, 20 e 30, carte di classe una volta e mezza più frequenti, copie senza limite. La lista del mazzo a destra, la curva di mana in basso a sinistra, i progressi dell'avversario in alto a destra (eroe scelto o no, carte, pronto; mai l'eroe né le carte). Quando entrambi premono “Pronto”, inizia una serie fino a tre vittorie; dopo ogni partita, la sala con il punteggio; si può abbandonare l'Arena o uscire al menu in qualsiasi momento.
- Il risultato di una partita dal tuo lato — Vittoria!, Sconfitta o Pareggio — sopra un'immagine semitrasparente (online prima c'era “Il giocatore N vince”).

### Verificato
- Pareggio: un Fuoco Infernale che uccide entrambi gli eroi dà un pareggio, ed entrambi gli eroi vanno in frantumi.

## [0.19.5] - 2026-10-12

### Corretto
- Sito: la sezione sul codice aperto mostrava “{tests}” invece del numero di test.

## [0.19.4] - 2026-10-12

### Aggiunto
- Un link al sito in Telegram, WhatsApp, Discord, Slack e altri messenger mostra un'anteprima con la schermata principale del gioco (una partita), il titolo e una descrizione.

## [0.19.3] - 2026-10-12

### Aggiunto
- Sito: la versione del gioco e un blocco “Novità” (le ultime voci del registro nella lingua della pagina), una sezione “In partita”, domande e risposte (requisiti, telefoni, dove sono salvati i mazzi, giocare offline, installare come app, cosa invia il gioco online, come segnalare un errore), una sezione sul codice aperto; il link al registro apre la lingua della pagina; sul telefono la pagina non scorre più di lato.

## [0.19.2] - 2026-10-12

### Modificato
- Il sito e il README corrispondono al gioco: allenamento con scelta del mazzo e dell'eroe del bot, dieci mazzi Classic famosi, il relay del gioco online, strumenti di debug nelle Impostazioni, emote con le parole degli eroi, set di illustrazioni e dorsi; i passi online usano i nomi dei pulsanti del gioco; tolte le affermazioni superate (nessun server, tutta l'arte disegnata dal codice).

## [0.19.1] - 2026-10-12

### Modificato
- Sito: nuove schermate (cronologia per turni, tracker del mazzo, lezioni prima delle missioni, strumenti di debug; la pagina russa mostra schermate in russo), testi aggiornati e dimensione del download (circa 61 MB). Sul telefono un tocco ingrandisce una carta del ventaglio e un doppio tocco la gira.

## [0.19.0] - 2026-10-12

### Aggiunto
- Al primo avvio il gioco chiede di scegliere la lingua; quella del sistema è evidenziata.

## [0.18.5] - 2026-10-12

### Modificato
- I danni casuali su più bersagli (Dardi Arcani, Furia Vendicativa, Bombarolo Pazzo, Tiro Multiplo, Fulmine Biforcato e simili) volano un proiettile alla volta; la salute del bersaglio scende a ogni colpo.

## [0.18.4] - 2026-10-12

### Aggiunto
- Elusivo: il servitore è avvolto da una foschia dorata scintillante, e la parola ha la sua finestra (magie e poteri eroe non possono bersagliarlo).

## [0.18.3] - 2026-10-12

### Aggiunto
- Le carte bruciate (mano piena) e i danni da affaticamento compaiono nella cronologia a sinistra: una casella propria con immagine e spiegazione al passaggio del mouse.

### Corretto
- Tutorial: il Cronista Cho non può essere attaccato finché ha servitori.

## [0.18.2] - 2026-10-12

### Modificato
- La sintesi vocale è stata tolta: il gioco non legge più ad alta voce nomi ed emote; le impostazioni Voce e Parlato sono state rimosse. Le battute degli eroi compaiono come testo in fumetti con la punta verso l'eroe.

### Corretto
- Una casella spuntata perdeva lo sfondo sotto il mouse.

## [0.18.1] - 2026-10-12

### Aggiunto
- Editor di scena: zone Segreti e Arma, la scelta di chi muove per primo e le pedine nell'elenco delle carte.

## [0.18.0] - 2026-10-12

### Modificato
- Gli strumenti di debug sono passati nelle impostazioni e sono una schermata a schede: "Scena" (costruire una scena col mouse: eroi, mana, danni, armatura, mano, campo, mazzo; il JSON accanto; la modalità con pulsanti di opzione), "Test interazioni" (scenari pronti per ognuna delle 534 carte, 1108 in tutto: scegli carta e scenario e si gioca in una vera partita con tutti gli effetti e i suoni), "Test carte" e "Test effetti".

## [0.17.1] - 2026-10-12

### Aggiunto
- In caso di sconfitta il ritratto dell'eroe va in frantumi.
- I simboli di fulmine e veleno restano fermi e pulsano con un suono leggero quando l'effetto si attiva.

### Corretto
- Tutorial: "Missione successiva" apre le spiegazioni in una schermata a sé; la schermata della ricompensa non blocca più.

## [0.17.0] - 2026-10-12

### Aggiunto
- La cronologia a sinistra è divisa per turni ("Turno N" nel colore del giocatore); passando su un'azione si vede cosa ha fatto e a chi: danni, cure, potenziamenti, congelamento, silenzio, morti, evocazioni, armi equipaggiate e i grida di battaglia e rantoli di morte innescati. Le carte nascoste dell'avversario restano nascoste.
- Il tracker del mazzo ha un proprio pulsante accanto al menu: "Il tuo mazzo" con immagini, ×2, carte esaurite oscurate e la probabilità di pescare ogni carta; "Giocate dall'avversario", un elenco che cresce con ×2.

## [0.16.2] - 2026-10-12

### Corretto
- Tutorial: dopo una vittoria, "Missione successiva" apriva le spiegazioni sotto la schermata della ricompensa e la schermata si bloccava.

## [0.16.1] - 2026-10-12

### Aggiunto
- Sotto il pulsante "Fine turno": la durata della partita e, online, il tempo rimasto del turno.
- Tutto sul tavolo si illumina sotto il mouse; un'arma si gira quando non è il turno del suo eroe.
- Servitori ed eroi dicono le loro battute (in gioco, in attacco, alla morte, emote, inizio partita, resa) quando c'è una registrazione; le emote degli eroi con parole proprie.

### Modificato
- La miccia del timer è una corda ritorta con una brace, scintille e fumo.
- Una carta bruciata si consuma dai bordi con un orlo incandescente.
- Un colpo all'eroe: numero del danno più grande; oltre 5 danni scuote di più con un suono pesante.
- Un eroe che può attaccare brilla di più.

## [0.16.0] - 2026-10-11

### Aggiunto
- Menu principale: Gioca apre un sottomenu con gioco online, allenamento e tutorial.
- Allenamento a passi: scegli un mazzo da un elenco con i ritratti degli eroi (o vai ai mazzi), poi l'avversario da una griglia 3×3, poi Gioca.
- Gioco online a passi: nome, mazzo, Crea partita o Unisciti; i codici hanno un pulsante Copia accanto.
- Tutorial: missioni con i ritratti dei boss; prima di ogni missione, spiegazioni illustrate dei nuovi concetti (parti della carta, combattimento, mana, magie, grido di battaglia, provocazione, carica, rantolo di morte, potere eroe, congelamento, armi).
- Collezione e mazzi in un'unica schermata: tutte le carte a sinistra con schede di classe, filtri per tipo, costo, rarità e ricerca; i mazzi a destra con copia, esporta ed elimina; un mazzo si modifica nello stesso posto.

### Corretto
- Gioco online: un relay TURN per le reti senza percorso diretto; l'ospite attende fino a 4 minuti la risposta dell'host e rinnova i candidati di connessione per tutto il tempo (prima il browser si arrendeva dopo pochi secondi).

## [0.15.3] - 2026-10-11

### Aggiunto
- La schermata di caricamento mostra la versione del gioco.

## [0.15.2] - 2026-10-11

### Modificato
- Gli emblemi di classe sono semplici e piatti; la spada della gemma d'attacco è più corta, punta in alto a destra, con l'impugnatura visibile in basso a sinistra; il fulmine sotto il ritratto è grande la metà; la boccetta di veleno è verde, più piccola e ferma.
- Silenzio: nastri rosa luminosi avvolgono il ritratto.
- Rantolo di morte: il teschio cresce dal servitore e sale.
- Un servitore con grido di battaglia prima prende il suo posto, poi la freccia verso il bersaglio parte da lui; il clic destro o la freccia riportata nella mano annulla, e la carta torna in mano.

### Corretto
- Le scintille di danno magico a volte si fermavano.

## [0.15.1] - 2026-10-11

### Modificato
- Le gemme di mana, salute, attacco, armatura e durabilità sono più piccole e lisce al centro per leggere meglio i numeri; i simboli sotto il ritratto sono più piccoli.

## [0.15.0] - 2026-10-11

### Aggiunto
- Immagini dell'interfaccia dipinte: cristallo di mana, goccia di salute, gemma d'attacco con spada, scudi di armatura e durabilità, scudo di Provocazione, teschio con ossa, boccetta di veleno, fulmine, emblemi di classe, un'immagine per l'affaticamento.
- I servitori velenosi (Cobra Imperiale, Assassina Paziente) hanno una boccetta di veleno.
- Una finestra della parola chiave per Ira.
- La carta di un servitore silenziato mostra il testo barrato da una croce rossa al passaggio del mouse.
- Il sovraccarico si vede subito: lucchetti arancioni sopra i cristalli per il turno seguente; un cristallo bloccato mostra un lucchetto invece di una croce.
- Una carta creata da una carta sul tavolo (Arcimago Antonidas, Ysera) vola da questa nella mano.

### Modificato
- I bagliori (giocabile, selezionato, bersaglio) sono sempre all'esterno di tutti gli effetti di una carta.
- Furia del Vento: raffiche su un'orbita inclinata, dietro e davanti alla carta.
- Furtività: una foschia attraverso cui l'immagine traspare appena; Congelato: uno strato di brina e un bordo ghiacciato.
- I segreti sul ritratto dell'eroe sono rotondi: viola per il mago, verdi per il cacciatore, gialli per il paladino.
- Le gemme di rarità sono rotonde, con ombra e riflesso.
- Il drago di un servitore leggendario copre solo la parte alta dell'ovale.

## [0.14.1] - 2026-10-11

### Modificato
- Il drago di un servitore leggendario sul tavolo si avvolge attorno all'ovale del ritratto.

### Corretto
- Nel browser il primo Cmd/Ctrl+V non incollava nulla invece del codice copiato (codice di un amico, importazione del mazzo).
- Gioco online: il tempo con la scheda nascosta non interrompe più l'attesa della connessione.
- Una carta in mano si può prendere premendo sotto la carta sollevata, dove si trovava.
- Le finestre delle parole chiave riappaiono passando su una carta in mano.

## [0.14.0] - 2026-10-11

### Aggiunto
- 10 mazzi classici pronti nel menu dei mazzi: Control Warrior, Midrange Shaman, Midrange Druid, Control Priest, Miracle Rogue, Midrange Paladin, Handlock, Freeze Mage, Midrange Hunter, Zoolock. Chi ha mazzi salvati li riceve una volta.

## [0.13.0] - 2026-10-11

### Aggiunto
- Mulligan: le carte sostituite volano nel mazzo, le nuove prendono il loro posto, la moneta compare girando con una luce dorata e poi tutta la mano scende. Le carte da sostituire hanno un sigillo rosso con una croce bianca.
- Affaticamento: una carta scura con un teschio e il suo danno vola dal mazzo vuoto all'eroe.
- Una carta bruciata (mano piena) si mostra e va in fiamme.
- Passando sul mazzo si vede anche quante carte ha in mano quel giocatore.

### Modificato
- Il mana che la carta sotto il mouse spenderebbe pulsa chiaramente, se basta.
- Il bagliore di carte e pulsanti giocabili è più stretto e più intenso sul bordo.

## [0.12.2] - 2026-10-11

### Modificato
- Le carte giocabili, i servitori, il potere eroe e il pulsante "Fine turno" hanno un bagliore morbido e pulsante invece di un contorno.

## [0.12.1] - 2026-10-11

### Aggiunto
- Passando il mouse su una carta in mano lampeggiano i cristalli di mana che spenderebbe, se si può giocare.

## [0.12.0] - 2026-10-11

### Aggiunto
- Effetti sul tavolo: magie, grida di battaglia, rantoli di morte ed effetti di inizio e fine turno lanciano proiettili dalla fonte a ogni bersaglio. All'impatto ogni servitore ed eroe mostra cosa gli succede: un'esplosione per i danni, scintille per la cura, frecce per potenziamenti e indebolimenti, un lampo per una nuova parola chiave, ghiaccio, un anello di silenzio, fumo di trasformazione, un portale di evocazione, un teschio di rantolo di morte, un bagliore di grido di battaglia, un vortice al cambio di controllo, uno scudo d'armatura.
- I numeri che cambiano sulle carte si ingrandiscono per un attimo con la loro gemma.
- La razza della carta (Bestia, Demone, Drago, Murloc, Robot, Totem, Pirata, Non Morto) su una targhetta in fondo alla carta.
- Un servitore immune brilla di bianco con scintille che gli girano attorno.

### Modificato
- Lo scudo di Provocazione segue il contorno del ritratto.
- "Il tuo turno" appare dopo gli effetti di fine turno.

## [0.11.0] - 2026-10-11

### Aggiunto
- Sei dorsi delle carte da scegliere nelle impostazioni: Classico, Orda, Druido, Arcano, Oro, Notte.
- Laboratorio effetti nel tavolo di debug: qualsiasi carta sul tavolo e in mano con le sue finestre; parole chiave, potenziamenti, indebolimenti, aure, danni, silenzio, sonno, cambi di costo e bagliori si attivano e disattivano in tutte le 8 lingue.

### Modificato
- Il tavolo cambia nel momento del colpo: numeri, scudi e morti appaiono quando l'attaccante tocca il bersaglio o arriva il proiettile della magia, non prima. Un servitore che muore svanisce con i suoi ultimi numeri.

### Corretto
- Nella versione web sopra il titolo del menu c'era un rettangolo bianco al posto del drago.
- Le carte nella pagina del gioco sono disegnate dal gioco stesso e appaiono come nel gioco.

## [0.10.0] - 2026-10-11

### Aggiunto
- Ogni carta ora ha la sua immagine generata.
- Il testo delle carte è impaginato a mano per ogni carta in ogni lingua: le righe, la dimensione del carattere e la posizione. Un controllo assicura che nessun testo esca dalla cornice o finisca sulle gemme; le righe sono equilibrate, i numeri restano con la loro parola, le parole chiave non vengono spezzate.
- Laboratorio carte (nel tavolo di debug): una carta in tutte le 8 lingue insieme, con le sue cornici e un elenco dei problemi; dimensioni, posizione e righe si possono cambiare e salvare.
- I servitori mostrano i loro cambiamenti in piccole finestre: potenziamenti con la carta che li ha dati, aure, valori impostati, parole chiave ottenute, Congelato, Silenziato. Finestre delle parole chiave anche nella collezione e nella creazione dei mazzi.
- Carte leggendarie: un fregio dorato e dritto con un drago lungo il bordo superiore della carta.
- La schermata di caricamento con l'aspetto attuale del menu.

### Modificato
- La spada dietro la gemma d'attacco sporge in alto a sinistra, oltre il bordo della carta, lontano dal testo.
- Contrasto più forte dei numeri sulle carte, soprattutto per i valori potenziati e danneggiati.

### Corretto
- Il testo francese di alcune carte mostrava "|4(point,points)" invece di "point" o "points".
- Nella pagina del gioco l'ultima lettera del titolo non è più tagliata.

## [0.9.0] - 2026-10-12

### Aggiunto
- Menu principale: uno sfondo di taverna generato con zoom lento, scintille volanti, un titolo dorato vettoriale con un drago e un riflesso che scorre; i pulsanti compaiono uno alla volta.
- Sfondi generati: la partita si gioca su un tavolo di pietra sopra un tavolo di taverna, la scelta del mazzo e la collezione si trovano in una biblioteca di taverna, le altre schermate in una taverna oscurata.
- Font Alegreya per l'interfaccia (latino, cirillico, greco) e pulsanti di legno in stile taverna con angoli arrotondati e cornice dorata; campi di input arrotondati, cursori dorati.
- I testi delle carte entrano sempre nella cornice: la dimensione del carattere viene adattata misurando per ogni carta in ogni lingua. Parole chiave in grassetto.
- Riquadri con la spiegazione delle parole chiave accanto alla carta ingrandita.
- Una spada dietro la pietra dell'attacco, un piccolo drago generato sulle carte leggendarie.
- Il potere eroe si capovolge dopo l'uso; il pulsante «Fine turno» si illumina di verde quando non ci sono più mosse.
- Filtro di rarità nella collezione e nella costruzione dei mazzi.
- Elenchi dei mazzi come nell'originale: una striscia con il ritratto dell'eroe dietro il nome del mazzo, una striscia con l'illustrazione della carta nell'elenco delle carte del mazzo, il costo su un cristallo, il riempimento del mazzo come barra.
- Il registro delle modifiche si apre nella lingua del gioco.
- Il gioco si può installare come app (PWA) e giocare offline dopo il primo caricamento.
- Sulla pagina del gioco gli screenshot sono in inglese.

### Corretto
- Le intenzioni ripetute o troppo frequenti dell'avversario non appesantiscono più il tavolo; la carta popup della cronologia non viene ricreata a ogni movimento del mouse; la conferma del mulligan cede al timer e alla perdita di connessione; una carta trascinata resta sopra il tavolo.

## [0.8.1] - 2026-10-11

### Corretto (dopo la revisione)
- Nelle partite online il timer poteva terminare da solo il nuovo turno mentre era ancora in corso l'animazione della mossa dell'avversario.
- Il clic destro durante il trascinamento di una carta lo annulla senza errori.
- Le carte in mano non vengono più disegnate sopra le impostazioni, il menu, il mulligan e la schermata di fine partita.
- Una creatura rimandata in mano o trasformata cambia sul posto, invece di «morire» con una nuova carta dal mazzo.

## [0.8.0] - 2026-10-11

### Aggiunto
- Tavolo come nell'originale: creature ovali con la pietra dell'attacco e la goccia della salute, scudo di pietra della provocazione, drago dorato sopra le leggendarie, cornici delle carte con nastro del nome e pergamena, ritratti degli eroi ad arco con lo stemma della classe.
- Effetti animati sul tavolo: furia del vento, scudo divino, copertura, congelamento, sonno, inneschi, ultimo desiderio, aure, furore, danno degli incantesimi, silenziamento.
- Trascinamento delle carte: la carta segue il cursore, le creature si scostano per fare posto all'inserimento, frecce curve per incantesimi, attacchi e potere eroe. Funziona anche la selezione con i clic.
- Animazioni: pescata dal mazzo, giocata (la carta dell'avversario si gira a metà), volo degli incantesimi, attacco di creature ed eroe, potere eroe, morte, ritorno in mano, mulligan, rivelazione di un segreto, banner «Il tuo turno», battute con l'eroe che «parla». Il bot aspetta la fine delle animazioni.
- Mano a ventaglio: la carta sotto il cursore si solleva e si ingrandisce.
- Mazzo accanto all'eroe: lo spessore dipende dal numero di carte, il numero esatto appare al passaggio del cursore.
- Menu a ingranaggio nell'angolo in alto a destra: cronologia, deck tracker, impostazioni, resa. Emote con il clic destro sul proprio eroe, «Silenzia» sull'eroe avversario.
- Barra della cronologia a sinistra: immagini delle carte giocate, al passaggio del cursore la carta, al clic la cronologia testuale.
- Nelle partite online si vede dove guarda l'avversario: la carta sollevata nella sua mano, la sua freccia rossa, l'evidenziazione della creatura.
- Immagini delle carte: illustrazioni generate (Codex locale), arte originale (solo per il gioco locale) e set personalizzati: qualsiasi cartella in `art/`; la scelta è nelle impostazioni. Dove manca l'immagine c'è un'illustrazione disegnata, diversa per ogni carta.
- Impostazione della velocità delle animazioni: da normale fino a 4 volte più veloce.
- Mazzo base per ogni eroe al primo avvio.
- Icone delle classi nella collezione, nella scelta dell'eroe e dell'avversario; i filtri di costo sono cristalli di mana.
- Pagina del gioco in 8 lingue, con immagini delle carte, ritratti degli eroi, ventaglio di carte, scintille e contatori.

### Modificato
- Nuova musica in stile taverna: liuto e arpa pizzicati, flauto, pad, basso, tamburello e shaker, eco e riverbero. Il menu ha un valzer tranquillo, in battaglia tre brani diversi da 60–90 secondi. Ogni partita inizia con un brano diverso dalla precedente, alla fine di un brano parte il successivo.
- Cristalli di mana al posto del testo «Mana 3/5».

## [0.7.0] - 2026-10-11

### Aggiunto
- Pagina del gioco su GitHub Pages: https://pycz2.github.io/classichs/ — intestazione animata, funzionalità, galleria di screenshot, russo e inglese; il gioco si può avviare direttamente sulla pagina.
- `README.md` con screenshot, funzionalità, compilazione e struttura del progetto.
- `tools/build_site.sh`: compilazione del sito e pubblicazione nel ramo `gh-pages`.

### Modificato
- L'esempio sul tavolo di debug è una posizione da vetrina: segreto, arma, provocazione, creature leggendarie, mano piena.
- Le battute russe del boss della prima missione usano il nome ufficiale «Boccalarga».

### Corretto
- I simboli assenti dal font venivano mostrati come quadrati: le icone delle creature (ultimo desiderio, innesco, silenziamento) ora sono vettoriali, la freccia è ASCII. Un test verifica che il font contenga ogni simbolo dell'interfaccia e delle traduzioni.

## [0.6.0] - 2026-10-11

### Aggiunto
- Interfaccia in 8 lingue: English, Русский, Deutsch, Français, Español, Português (Brasil), Italiano, Polski. La lingua predefinita è quella del sistema; il cambio di lingua nelle impostazioni è immediato, senza riavvio.
- Schermata delle impostazioni (dal menu e dalla partita): lingua, volume di musica, suoni e voce, doppiaggio, vibrazione dello schermo, schermo intero, nome del giocatore.
- Arte vettoriale per ogni carta, eroe e potere eroe: motivo in base a nome, razza, tipo e classe (fuoco, ghiaccio, yeti, pecora, murloc, arma e altri).
- Suoni degli eventi del tavolo e due melodie (menu e battaglia); tutti i suoni sono sintetizzati, senza file esterni.
- Doppiaggio con la voce di sistema nella lingua dell'interfaccia: nomi delle creature leggendarie e dei nuovi eroi, emote, battute dei boss del tutorial.
- Registro delle modifiche: un clic sulla versione nell'angolo del menu apre tutta la cronologia delle modifiche del gioco.
- Deck tracker in partita: il proprio mazzo, le carte rimaste con la probabilità di pescare ciascuna come prossima, le carte giocate dall'avversario. Ogni vista si può nascondere; la scelta viene ricordata.
- Timer del turno nelle partite online: 75 secondi, negli ultimi 15 secondi si accende la miccia; scaduto il tempo, il turno termina da solo.

### Modificato
- La cronologia dei turni segna l'inizio del turno in base all'evento, non al testo; il pannello della cronologia non scorre in basso mentre il giocatore legge le vecchie voci.
- I motivi di desincronizzazione e il nome predefinito del giocatore vengono tradotti.

### Corretto
- Il pulsante «Arrenditi» non diventava «Menu» dopo la fine della partita.

### Corretto (dopo la revisione)
- La cronologia dei turni, una volta aperta, mostra i nuovi turni.
- Il cambio di lingua in partita cambia anche i titoli del deck tracker e della cronologia, il nome del bot e le finestre aperte.
- I testi lunghi delle carte non escono più dalla cornice.

## [0.5.0] - 2026-10-11

### Aggiunto
- Tutorial: sei missioni con Jaina, come nell'originale — Boccalarga, Millhouse Manalampo, Ramingo Cho, Re Mukla, Hemet Nesingwary, Illidan Grantempesta.
- Suggerimenti passo dopo passo, battute dei boss, regole delle prime missioni (non si può perdere, non si può terminare il turno con mana o attacco non spesi), il potere eroe si sblocca nella quinta missione.
- Carte dei boss del tutorial: Boccalarga SPACCA!, Barile, Urto a Terra, Volontà di Mukla, Trascendenza, Fiamme di Azzinoth, Scarica delle Fiamme e altre.
- Schermata del premio dopo la vittoria; i progressi del tutorial vengono salvati, le missioni completate si possono rigiocare.

## [0.4.0] - 2026-10-11

### Aggiunto
- Partita online nel browser senza un server proprio: WebRTC direttamente tra i browser, STUN pubblico di Google. L'host crea un codice d'invito, l'ospite risponde con un codice di risposta; i codici si scambiano con qualsiasi messenger.
- Sincronizzazione della partita: entrambe le parti verificano lo stato del gioco dopo ogni mossa; in caso di divergenza, versione errata del gioco o caduta della connessione viene mostrato un messaggio chiaro.
- Nome del giocatore (lo vede l'avversario), 6 emote e il pulsante «silenzia l'avversario».

### Corretto (dopo la revisione)
- Il mulligan nelle partite online viene scelto da entrambi i giocatori contemporaneamente.
- Connessione più affidabile tra reti diverse: il gioco aspetta che il browser trovi l'indirizzo esterno; c'è un timeout di connessione con un suggerimento.
- Messaggi chiari: «l'avversario è uscito», «versione diversa del gioco», «dati delle carte diversi», «desincronizzazione».
- Le emote non si possono inviare più di una volta ogni 1,5 secondi; «silenzia» nasconde subito l'emote mostrata.

## [0.3.0] - 2026-10-11

### Aggiunto
- Collezione: tutte le 382 carte, pagine da 8 carte, schede delle classi, filtro per costo, ricerca, carta ingrandita al passaggio del cursore.
- Mazzi: quantità illimitata, creazione, modifica, copia, eliminazione; regole di Hearthstone (30 carte, 2 copie, 1 leggendaria, solo carte della propria classe e neutrali).
- I mazzi vengono salvati nel browser e restano dopo il riavvio; un file danneggiato non va perso, ma viene spostato in `decks.bad.json`.
- Codici mazzo di Hearthstone: esportazione nel formato Classic; importazione dei codici dei formati Classic, Standard e Wild, compresi i vecchi mazzi del 2014–2016 con le carte originali e il testo copiato dal client.
- Allenamento: scelta del proprio mazzo; un mazzo incompleto non può essere avviato.

### Corretto (dopo la revisione)
- L'errore di importazione del codice viene mostrato nella finestra di importazione.
- Un mazzo con una carta scomparsa si apre e si può modificare; il giocatore viene informato se il file dei mazzi era danneggiato (la copia viene salvata).
- Si importano i codici dei mazzi con altri aspetti degli eroi (Magni, Medivh ecc.) e i codici da testo con un titolo nella prima riga.
- Il mazzo viene salvato dopo ogni modifica, non solo con il pulsante «Done».

## [0.2.0] - 2026-10-11

### Aggiunto
- Menu principale, scelta della classe per l'allenamento, mazzi base delle nove classi.
- Tavolo di gioco: eroi, poteri eroe, armi, segreti, tavoli, mani, mana; mulligan, Scegli uno, scelta di Tracciamento, schermata di fine partita.
- Controllo con il mouse: carta → variante → posto sul tavolo → bersaglio; attacco; potere eroe; suggerimento con la carta ingrandita.
- Effetti semplici: numeri fluttuanti di danno e cura, ombra della creatura morta, vibrazione dello schermo in caso di danno forte.
- Bot per l'allenamento: prova le azioni su una copia della partita e sceglie la migliore.
- Cronologia dei turni durante la partita: tutte le mosse dall'inizio, senza limite di lunghezza; le carte pescate dall'avversario sono nascoste.
- Tavolo di debug: scenario in JSON, ricerca di una carta e aggiunta alla mano, al tavolo o al mazzo; partita contro il bot o per entrambe le parti; pulsante «Posizione → JSON».

### Corretto (dopo la revisione)
- Una creatura si può mettere tra altre cliccando su una creatura vicina.
- La cronologia non mostra all'avversario le carte scartate da Tracciamento.
- Il tavolo di debug segnala i tipi di campo errati dello scenario e non avvia una partita rotta.
- La resa richiede una conferma.
- Il bot ragiona più in fretta nelle posizioni grandi.

### Corretto
- Un segreto conta come incantesimo: lo vedono Dragone di Mana, Arcimago Antonidas, Piromante Selvaggio, Banditore di Meccania, Insegnante Violacea, Manadipendente; Controincantesimo annulla il segreto.
- Follia d'Ombra: la creatura rubata può attaccare anche se ha attaccato nel turno precedente del proprietario.
- Tracciamento non scarta le carte che il giocatore non ha visto.
- Mulligan: il risultato non dipende dall'ordine in cui i giocatori hanno confermato la scelta (importante per le partite online).
- Ci si può arrendere in qualsiasi momento, anche nel turno dell'avversario e durante il mulligan.
- Gli scenari conservano il costo delle carte in mano, lo stato dell'eroe e il contatore delle creature giocate; un errore nello scenario produce un messaggio, non un arresto anomalo.
- Prole della Luce non dipende dall'ordine delle aure; Copertura non rimuove la Furtività propria della creatura; Trappola di Serpi non scatta con il tavolo pieno.
- Un'azione non valida (ad esempio dalla rete) viene rifiutata senza modificare lo stato.

## [0.1.0] - 2026-10-11

### Aggiunto
- Struttura del progetto Godot 4.7 e runner dei test.
- Dati di 382 carte collezionabili del formato Classic (giugno 2014), dei token e delle carte del tutorial in 14 lingue.
- Motore: inizio partita, mulligan, Moneta, turno, mana, Sovraccarico, Fatica, carte bruciate, scongelamento di Congelato.
- Motore: cronologia completa della partita (`history`) — ogni azione e tutti i suoi eventi dall'inizio della partita.
- Motore: giocata delle carte, Grido di Battaglia, Combo, Scegli uno, segreti, armi, attacchi, Provocazione, Furtività, Furia del Vento, potere eroe, elenco delle azioni legali.
- Motore: scenari — creazione di qualsiasi posizione da JSON e salvataggio della posizione corrente in JSON (base del tavolo di debug).
- Carte: poteri eroe di tutte e 9 le classi, INFERNO!, Aculeo Mentale, Angoscia Mentale, Moneta.
- Carte: neutrali Basic (43).
- Carte: neutrali Classic COMMON (40).
- Carte: neutrali Classic RARE (36).
- Carte: neutrali Classic EPIC (11).
- Carte: neutrali leggendarie, premio e promo (27) e i loro token: Banana, carte Sogno, Power Chord, invenzioni di Gelbin Meccatork, Totem della Vita.
- Carte: Druid (25) e varianti Scegli uno.
- Carte: Hunter (25), segreti del cacciatore, Tracciamento.
- Carte: Mage (25), segreti del mago.
- Carte: Paladin (25), segreti del paladino.
- Carte: Priest (25).
- Carte: Rogue (25), Combo.
- Carte: Shaman (25), Sovraccarico.
- Carte: Warlock (25), Sire Jaraxxus.
- Carte: Warrior (25). Tutte le 382 carte collezionabili del formato Classic sono implementate.
- Verifica di completezza: ogni carta con un effetto ha un hook; 1000 partite casuali senza errori; il motore funziona nella build web, l'hash coincide con quello nativo.
