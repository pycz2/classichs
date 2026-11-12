# Registro delle modifiche

Formato: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Versioni: [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

### Aggiunto
- Un contatore dei fotogrammi al secondo: l’interruttore «Contatore FPS» nelle impostazioni (spento di default) li mostra in piccolo nell’angolo in alto a sinistra di ogni schermata.

## [0.70.0] - 2026-11-12

### Aggiunto
- **Undici nuovi giochi, le espansioni dopo Naxxramas.** Ognuno ha tutte le carte dei giochi precedenti (Base, Classiche, Naxxramas e i successivi in ordine), e ogni carta è com’era il giorno dell’uscita dell’espansione: costo, statistiche, razza, testi in 8 lingue. Ogni gioco ha i suoi modelli di mazzo della meta di allora (da 10 a 19), bot che lo giocano, un aspetto proprio e un simbolo dell’espansione.
- Goblin vs Gnomi 2014 (carte all’8 dicembre 2014): Robot, pezzi di ricambio, Mega Furia del Vento, Testa di Mimiron.
- Massiccio Roccianera 2015 (2 aprile 2015): Draghi e carte «se hai un Drago in mano», Thaurissan, Nefarian.
- Il Gran Torneo 2015 (24 agosto 2015): Ispirazione, Giostre, Poteri Eroe migliorati.
- La Lega degli Esploratori 2015 (12 novembre 2015): Rinvenire, Reno Jackson, Brann Barbabronzea.
- Sussurri degli Dei Antichi 2016 (26 aprile 2016): C'thun e i suoi rituali, N'zoth, Yogg-Saron e le dodici modifiche alle carte Classiche di quel giorno.
- Una Notte a Karazhan 2016 (11 agosto 2016, la prima ala): i portali, Medivh il Guardiano e Atiesh, Principe Malchezaar, Barnes.
- I Bassifondi di Meccania 2016 (1º dicembre 2016): Golem di Giada, Kazakus, carte di tre classi insieme.
- Viaggio a Un'Goro 2017 (6 aprile 2017): Missioni e le loro ricompense, Adattamento, Elementali, servitori dormienti.
- Cavalieri del Trono di Ghiaccio 2017 (10 agosto 2017): le carte eroe dei Cavalieri della Morte, Furto Vitale, una Bestia Zombi fatta di due Bestie.
- Coboldi & Catacombe 2017 (7 dicembre 2017): servitori direttamente dal mazzo al tabellone, Pietre Magiche che crescono, armi leggendarie.
- Il Bosco Tetro 2018 (12 aprile 2018): Eco, Assalto, carte per mazzi solo di costo pari o solo di costo dispari (Genn e Baku).
- I nuovi giochi non sono nelle build del client, quindi le app per computer, Android e browser non sono cresciute. Scarica un gioco da un server o installa il file ClassicHS-x.y.z-<gioco>.cardpack dalla pagina della versione. Ogni gioco è indipendente e non ne richiede altri: porta con sé le immagini delle carte più vecchie, e le nuove carte hanno semplici immagini disegnate.
- Le carte in mano la cui condizione vale in questo momento brillano di giallo: Combo, «se il tuo mazzo non ha carte doppie», «se hai un Drago in mano» e altre.
- Le carte delle espansioni mostrano il simbolo dell’espansione, anche accanto alla carta grande; la collezione ha un filtro per espansione.
- Il tabellone e la cronologia della partita mostrano le nuove meccaniche: una Giostra con una carta di ogni mazzo, il progresso di una Missione accanto al suo eroe, servitori dormienti, un turno extra, carte eroe con la loro Armatura, Furto Vitale, carte di più classi.
- Nel tuo pacchetto locale con i suoni, le carte leggendarie hanno una musica propria: suona quando la carta viene giocata, e intanto la musica di sottofondo si abbassa.

### Modificato
- La miccia del turno brucia verso il pulsante Fine turno, come in Hearthstone.
- Ogni lato ha al massimo 5 Segreti, come in Hearthstone dal 2014. Un sesto Segreto non si può giocare dalla mano, lo Scienziato Pazzo con cinque lascia il suo Segreto nel mazzo, e la Mistica di Kezan distrugge un Segreto invece di prenderlo.
- Un pacchetto può pesare fino a 1 GiB (2 GiB decompresso), nel client e su un server, anche il pacchetto di un giocatore. Il server legge un pacchetto dal disco a pezzi e non lo tiene mai tutto in memoria.
- Il server installa i suoi giochi inclusi in background: dopo un aggiornamento accetta subito i giocatori, e un nuovo gioco compare nell’elenco appena supera il controllo.

### Corretto
- Un bot che non riesce a fare la sua mossa (per esempio dopo un errore nello script di una carta) non la ripete più all’infinito: si ferma con un solo errore.
- Il testo tedesco del Potere Eroe migliorato del Paladino in Classico non mostra più parentesi vuote.

## [0.67.0] - 2026-11-11

### Aggiunto
- Bot nei tornei: il creatore aggiunge bot di un livello scelto (Facile, Medio, Difficile, Difficilissimo — due per livello sul server) fino al limite di giocatori e può toglierli. I bot portano mazzi del gioco, accettano i loro incontri, bannano, scelgono un mazzo e giocano ogni partita fino alla fine; i loro incontri si svolgono insieme. Il creatore può sempre guardare gli incontri del torneo; i replay vengono conservati. Un bot impegnato in un altro torneo è libero solo quando quello finisce.

## [0.66.0] - 2026-11-10

### Aggiunto
- Pannello di amministrazione, pagina di un giocatore: per ogni gioco — il grado (grado, stelle, Leggenda, serie, MMR nascosti; ritorno all’inizio della stagione), le impostazioni del gioco, i mazzi (le carte, copia del codice, aggiunta da un codice verificato con le regole, rinomina, eliminazione, copia a un altro giocatore); la corsa dell’Arena (vittorie, sconfitte, azzeramento, fine); il tag. Le modifiche arrivano subito al giocatore se è online e finiscono nel registro. Il codice di un mazzo (formato di Hearthstone) si può copiare ovunque il pannello mostri dei mazzi: statistiche, pagina di un incontro, partecipanti di un torneo.

## [0.65.0] - 2026-11-10

### Aggiunto
- Difficilissimo sul server: i bot dell’admin possono giocare a quel livello, e una Leggenda in classificata che aspetta a lungo un avversario riceve un bot automatico Difficilissimo invece di Difficile (3 secondi per decisione sul server).

## [0.64.0] - 2026-11-10

### Modificato
- Il bot Difficilissimo dell’allenamento è più forte: cerca un piano per tutto il turno (ricerca a fascio), guarda la risposta dell’avversario e il proprio turno successivo, e giudica le posizioni con un modello appreso da 2000 partite. Vince il 60% delle partite contro Difficile (400 partite con 19 mazzi) e il 72% contro Medio. Come prima, pensa fino a 6 secondi per decisione e finisce 10 secondi prima della fine del suo turno.

## [0.63.0] - 2026-11-10

### Aggiunto
- Pannello di amministrazione, statistiche: una matrice classe contro classe (vittorie della riga contro la colonna, partite, dal rosso al verde, specchi sulla diagonale, totale di ogni classe); periodi passati da scegliere — ieri, qualsiasi giorno passato, settimana, mese, anno. Le statistiche giornaliere di mazzi e carte restano 400 giorni; le statistiche occupano quasi metà dello spazio di prima.

## [0.62.0] - 2026-11-10

### Aggiunto
- Pannello di amministrazione: la versione del server nell’angolo di ogni pagina; la panoramica mostra quanto spazio occupano il database e l’archivio dei pacchetti.
- Pannello di amministrazione: il replay di qualsiasi partita sulla sua pagina — Play lo apre in basso come nel client (una versione web ridotta con il solo visore dei replay; prende il pacchetto del gioco dal server). Si chiude con la sua X o cambiando pagina.
- Pannello di amministrazione: statistiche in stile HSReplay per gioco — percentuale di vittorie delle classi per modalità e grado, i 20 mazzi migliori e i 5 migliori di ogni classe, le carte (in quanti mazzi, copie, vittorie dei mazzi, quanto vengono giocate e le vittorie quando giocate, il mulligan: tenuta o sostituita), per quest’ora, oggi, questa settimana, questo mese, quest’anno e da sempre, con grafici e i nomi inglesi delle carte. Aggiornate dopo ogni partita; le partite precedenti arrivano dai loro replay.

## [0.61.0] - 2026-11-10

### Aggiunto
- I bot del server giocano a tutti i giochi del server, non solo a Classico: qualunque gioco incluso o caricato. Se nel tempo impostato nel pannello di amministrazione non si trova un avversario, arriva un bot con un mazzo dai modelli di quel gioco (o il mazzo iniziale di una classe) e gioca con le sue carte.
- Nell’allenamento torna il bot Difficilissimo — il primo bot difficile: valuta ogni azione in fino a 200 ipotesi sulle carte nascoste e l’intero turno dell’avversario. Pensa finché al suo turno restano più di 10 secondi, poi prende il meglio trovato e chiude il turno in fretta, così non si blocca mai e non salta turni.

## [0.60.0] - 2026-11-10

### Aggiunto
- **Un nuovo gioco, Naxxramas 2014**: tutte le carte Base e Classiche e le 30 carte della Maledizione di Naxxramas con le loro pedine, ognuna com’era all’uscita dell’avventura (22 luglio 2014): Becchino +1/+1, Rigurgitatore di Melma 3/5, Reincarnazione a 2, nessuna razza Non Morto, l’Arco di Corno d’Aquila cresce solo con i tuoi Segreti (patch 1.1.0.6024).
- Nuove meccaniche nel motore: Rantoli di Morte doppi (Barone Rivendare), Velenoso (Maexxna), i servitori morti nel turno tornano (Kel'Thuzad), gli incantesimi avversari costano di più (Loatheb), Feugen e Stalagg, Scienziato Pazzo, Semi Velenosi, Reincarnazione e altro.
- 10 modelli di mazzo della meta del 2014, bot che giocano a Naxxramas, un aspetto proprio (menu, tabellone, schermate dei risultati) e illustrazioni 2D semplificate per le nuove carte; si installa come un pacchetto normale ed è sul server.

## [0.51.0] - 2026-11-10

### Modificato
- Le carte Classiche e Base sono come a giugno 2014 (l’ultima patch prima di Naxxramas), secondo i dati di gioco dell’epoca e la cronologia della Hearthstone Wiki: Capobanda dei Defias 2/2; Flagello Funesto infligge 2 ed evoca uno dei sei demoni del 2014; l’Arco di Corno d’Aquila cresce con qualunque Segreto rivelato; la Sorella Ridente costa 3; torna la Succube (non il Vilsegugio); l’Ombra del Nulla sparisce a fine turno; i Robot e i Non Morti del 2014 non hanno razza; 37 testi e oltre 40 nomi come nel 2014 in tutte le lingue.
- Nozdormu funziona: finché è sul tabellone, un turno dura 15 secondi — su un server, nell’allenamento contro il bot e nella partita con codice (con la miccia).

### Aggiunto
- Le voci originali di carte ed eroi nel tuo pacchetto locale: il suono e la battuta di un servitore quando arriva, attacca e muore, i suoni degli incantesimi, le emote e le battute degli eroi (mana insufficiente, non può attaccare, inizio). Il pacchetto si costruisce in locale (tools/fetch_original_sounds.py, pack.py --sound-set e --voice) e non viene inviato da nessuna parte.
- Nel tuo pacchetto locale di illustrazioni: le illustrazioni del 2014 delle carte cambiate in seguito (Succube, Arpia Furiavento, Custode dei Segreti, Sventramento, Morso, Colpo Mortale, Spaccacrani).

### Corretto
- Gli effetti durante un attacco avvengono a metà strada: l’attacco si ferma, il Segreto si rivela e agisce del tutto (Nobile Sacrificio — l’attacco va sul Difensore, Depistaggio — verso il nuovo bersaglio, Trappola Congelante — l’attaccante torna in mano, Vaporizzazione — l’attaccante muore per strada, Trappola Esplosiva), e anche la cura della Campionessa di Verargento a metà strada.
- Lo Scudo Divino si rompe nello stesso istante in cui l’attaccante subisce i danni.
- La resistenza di un’arma sotto quella della carta è rossa, come la salute ferita.
- Il Danno Magico su un servitore ha un nuovo effetto magico; un servitore che dorme emette z verdi; gli effetti nascosti (Corruzione e altri) sono segnati sul servitore e descritti nella sua carta grande.
- Le carte scartate volano in alto e bruciano; una carta copiata dalla mano avversaria arriva da quella mano.
- Il pacchetto di un giocatore su un server può pesare fino a 128 MiB (come nel client).

## [0.50.0] - 2026-11-09

### Aggiunto
- **Tornei** su un server: chiunque ne crea uno da «Tornei» nel menu del gioco. Formati: eliminazione (una o due vite, con tabellone dei perdenti), sistema svizzero, girone all’italiana, squadre (Scheveningen). Serie Conquest o Last Hero Standing, da Bo1 a Bo7, con o senza ban. Iscrizione, mazzi di classi diverse, il tabellone, i piazzamenti con le medaglie per i primi 3, schede In arrivo, Conclusi, Chiusi. Un minuto per ogni passo di un incontro (accettare la partita, ban, scelta del mazzo).
- **Replay**: ogni partita sul server viene conservata; le ultime 10 sono in «Replay» nel menu del gioco. Si guardano scorrendo per turno e per azione, con entrambe le mani scoperte. Esportazione e importazione di un file di replay.
- **Guardare** la partita di un amico: «Guarda» nella lista degli amici. Nei tornei il creatore e i giocatori eliminati possono guardare gli incontri a mani scoperte, se il creatore lo consente.
- **Registrazione con chiave d’invito**: l’admin la attiva nel pannello di amministrazione, crea le chiavi (una nota, quanti utilizzi) e vede chi è arrivato con quale chiave.
- Nel pannello di amministrazione: l’attesa prima che un bot sostituisca un avversario reale (da 0 a 10 minuti), le pagine delle chiavi d’invito e dei tornei, il download del replay di una partita.
- Parallasse nel menu principale: l’immagine, le particelle e la polvere seguono il mouse o l’inclinazione del telefono.

## [0.42.2] - 2026-11-05

### Modificato
- Touchscreen: non si può più trascinare una carta direttamente dalla mano piccola. Il primo tocco apre solo la mano (come nella 0.42.0).

## [0.42.1] - 2026-11-05

### Corretto
- La ricerca di una partita su un server con un mazzo salvato sul server non finiva mai: il server rifiutava il mazzo per un campo di note. Ora il client non lo invia, il server accetta questi mazzi e un rifiuto ferma la ricerca.
- Le partite su un server (Arena, classificata, normale) si bloccavano quando un servitore entrava sul tabellone: i numeri della risposta del server non corrispondevano a quelli sul tavolo.
- Un mazzo pieno non copre più il timer della partita: la pila cresce verso il basso.
- Un servitore lasciato sul tabellone durante un’animazione si mette subito nel suo spazio e aspetta lì, invece di tornare nella mano.
- Touchscreen: puoi trascinare subito una carta dalla mano piccola, senza toccarla prima per aprirla.

## [0.42.0] - 2026-11-03

### Aggiunto
- Touchscreen (Android e browser): la mano aspetta piccola in basso a destra; un tocco la apre, un tocco fuori la chiude.
- Touchscreen: toccare una carta della mano la mostra soltanto. Una carta si gioca solo se la trascini sopra il terzo inferiore dello schermo; lasciata più in basso, torna nella mano.
- Touchscreen: tutte le liste (mazzi, collezione, giochi, server, amici, chat, cronologia e altre) scorrono con il dito, anche se il gesto parte da un pulsante; un gesto veloce continua per inerzia.
- Touchscreen: una pressione lunga mostra il suggerimento (le carte di un mazzo, il tuo e quello dell’avversario; perché un mazzo non si può giocare; cosa fanno i pulsanti) e funziona come clic destro (le emote del tuo eroe).
- Touchscreen: nella collezione e nel draft dell’Arena un tocco aggiunge la carta; una pressione lunga la mostra soltanto.

### Modificato
- Il mazzo sul tavolo è molto più spesso con tante carte e più sottile con poche.

### Corretto
- Un servitore che metti giù resta nello spazio scelto mentre agisce il suo Grido di battaglia, e dopo non si muove più (prima tornava per un attimo verso la mano e poi rientrava).

## [0.41.1] - 2026-11-03

### Corretto
- «Carica un gioco» su un server ora propone anche la tua versione di un gioco che il server ha già (stesse regole, immagini tue): per esempio Classic con il tuo set di illustrazioni.

## [0.41.0] - 2026-11-03

### Aggiunto
- Un tutorial per Neonfall: sei missioni con i loro boss, dalla prima carta a tutte le meccaniche del gioco, in otto lingue.
- Aggiungere un gioco da un file mostra cosa succede: la lettura del file con una barra di avanzamento, poi i controlli.

### Corretto
- Le lettere russe non si vedevano nel pacchetto Classic: il suo font dei titoli non ha il cirillico. Le lettere mancanti arrivano ora dal font del client e il titolo del menu del gioco è scritto in maiuscolo.
- Un servitore con Grido di battaglia prima si posa sul tavolo (gli altri gli fanno spazio), poi agisce il Grido di battaglia, poi si sistema.
- Una carta pescata da un'altra carta (Ingegnere novizio) arriva dal mazzo, non dal servitore.
- Il set di immagini proprio di un pacchetto importato (costruito dalla cartella del suo autore) ora si può scegliere.

## [0.40.0] - 2026-11-03

### Modificato
- Il gioco si chiama **Classic Heroes Showdown** (in breve Classic HS). Ora è un motore per giochi di carte: ogni gioco è un pacchetto con le sue regole, carte, aspetto, musica, tutorial e modelli di mazzo.
- Un nuovo menu: Gioca, Impostazioni, Esci. Gioca → Diretto (la libreria dei giochi, poi il menu del gioco scelto nel suo stile) o Server (connessioni, accesso, la pagina del server con amici e giochi del server).
- Impostazioni generali: lingua, volume, dorso delle carte, velocità delle animazioni, tremolio, schermo intero. I set di immagini e musica si scelgono per gioco (salvati sul server in modalità server); gli strumenti di debug sono nelle impostazioni dentro un gioco.
- I mazzi restano per gioco; su un server sono i mazzi del server di quel gioco, e quelli locali si possono copiare lì. Niente più mazzi pronti nella lista: un nuovo mazzo parte da zero o da un modello del pacchetto.
- Il tutorial e gli effetti di scena (pioggia, neve, braci) fanno ora parte del pacchetto. Lo stile taverna è passato nel pacchetto Classic; il client ha un aspetto neutro.

### Aggiunto
- Strumenti per pacchetti nella libreria: costruire un gioco da una cartella, controllarlo (file, JSON, script Lua con numero di riga, immagini, traduzioni, tutorial), giocare partite di prova tra bot, installarlo.
- Il sito ha una sezione «Per sviluppatori»: creare il proprio gioco, script delle carte in Lua, riferimento dell'API del motore, controlli e test, una mappa interattiva dell'architettura. La pagina iniziale è nello stile Neonfall.
- All'aggiornamento le impostazioni si spostano da sole: set di immagini e musica su Classic, server sulle connessioni, i tuoi mazzi sul loro gioco.

## [0.32.0] - 2026-11-02

### Aggiunto
- I mazzi possono restare sul server di gioco: il simbolo della nuvola sul mazzo. Il mazzo si salva a ogni modifica e compare sugli altri dispositivi dopo l'accesso.
- Un nuovo set di immagini «2D semplice» per Neonfall.
- Telefoni: una pressione lunga su un campo di testo apre un menu (Incolla, Seleziona tutto, Copia, Taglia); la password di accesso ha un pulsante Incolla.

### Corretto
- Le mosse si vedono in ordine, passo per passo: la carta dell'avversario esce dalla mano, una freccia mostra il bersaglio e ogni effetto si vede da solo (Missili arcani e Bombarolo pazzo colpiscono uno alla volta). Vale in entrambi i sensi e anche con animazione veloce.
- Mulligan: le carte sostituite tornano nel mazzo, le nuove prendono il loro posto, poi compare la Moneta e le carte vanno in mano nello stesso ordine.
- Android: una password copiata non si poteva incollare nel campo di accesso.
- Durante la ricerca di una partita sul server funziona solo Annulla: altre modalità, l'Arena, l'uscita e il cambio di gioco aspettano che la ricerca sia annullata.
- La versione web non carica più una versione vecchia dalla cache: una nuova versione arriva con un normale ricaricamento.

## [0.31.0] - 2026-10-30

### Aggiunto
- Allenamento contro un bot intelligente del livello scelto: facile, medio o difficile. È lo stesso bot del server; vede solo le proprie carte. Funziona su tutte le piattaforme e offline; il bot pensa in sottofondo e il gioco non si blocca.
- Server: chi aspetta da solo 30 secondi nella coda classificata, normale o dell'arena riceve un auto-bot per una partita. La sua forza segue il punteggio nascosto del giocatore; nell'arena, le vittorie della run.
- I bot dell'arena prendono un eroe a caso tra i tre; il bot facile sceglie le carte a caso, il medio quasi sempre le migliori, il difficile sempre le migliori per la curva di mana.
- Passando sopra una carta si vedono le carte che crea o evoca (pedine, trasformazioni, carte Scegli uno, il potere eroe).
- L'editor dei mazzi mostra la curva di mana sopra la lista delle carte.

### Corretto
- I bot del server non si bloccano più per minuti con il tavolo pieno e non perdono più per mosse in ritardo. Una mossa arrivata dopo la fine del turno viene rifiutata senza penalità, e questo protegge anche i giocatori con connessione lenta.
- Il motore delle regole è più veloce: copiare una partita circa 10 volte, una mossa 3,5 volte.

## [0.30.0] - 2026-10-26

### Aggiunto
- Il gioco tramite codici (diretto, senza server) ora funziona non solo nel browser ma anche su Windows, macOS, Linux e Android. Anche tra piattaforme diverse, per esempio browser contro Android.

### Corretto
- Firefox: Ctrl+V e Cmd+V non incollavano il testo nei campi, e un clic su un campo apriva un menu «Incolla». Ora incollare funziona e il menu non compare più.

## [0.29.2] - 2026-10-25

### Corretto
- Android: l'app non riusciva a raggiungere un server di gioco — accesso, registrazione, gioco online, download dei giochi. Mancava il permesso di accesso a Internet; ora c'è e la build lo verifica.

## [0.29.1] - 2026-10-24

### Aggiunto
- Amministrazione del server: un'icona della scheda propria — la tessera dorata con il rombo scuro del logo.

## [0.29.0] - 2026-10-24

### Aggiunto
- Bot sul server: il server fa giocare i propri giocatori di Classic — classificata, normale e Arena — così c'è sempre qualcuno con cui giocare. L'amministrazione del server ha una nuova pagina “Bots”: quanti, la forza (facile, medio, forte), le modalità, l'orario e le pause; avvio e arresto a caldo; cosa fa ognuno, la sua partita vista da lui, l'ultima decisione e il registro.
- I bot giocano onestamente: come ogni giocatore, con lo stesso protocollo, e vedono solo il proprio lato; stimano le carte nascoste dell'avversario con le probabilità.

## [0.28.4] - 2026-10-24

### Aggiunto
- Un nuovo set di immagini per Classic, “Fotorealistico”: tutte le 534 carte in stile fotorealistico con pochissimi dettagli. Sceglilo in Giochi → Classic 2014 → Immagini delle carte (o nelle impostazioni).

### Corretto
- Android: il gioco non si blocca più sulla schermata iniziale. La build comprimeva i giochi integrati (pacchetti) nell'APK e Android impiegava minuti a leggerli; ora sono salvati senza compressione e il gioco si apre in pochi secondi.
- Browser: Ctrl+V (Cmd+V) in un campo di testo incolla ciò che c'è ora negli appunti. Prima il primo incolla dava il contenuto precedente (o niente), ad esempio con una password copiata da un gestore di password.
- Android: il campo della password è segnato come password, così la tastiera e il gestore di password possono proporre quella salvata; l'indirizzo del server ha una tastiera per indirizzi.
- Telefoni: il campo di testo sale sopra la tastiera a schermo; prima la tastiera copriva i campi in basso e non si vedeva cosa si scriveva. Il suggerimento nell'elenco dei server non finisce più sotto il pulsante “Chiudi”.

## [0.28.3] - 2026-10-24

### Corretto
- Android: la libreria delle regole del gioco è compilata per pagine di memoria da 16 KB (telefoni con Android 15 o più recente). Questi telefoni avviavano il gioco in modalità di compatibilità o non lo avviavano.
- Nessun server predefinito: il gioco si avvia e si gioca senza server; aggiungine uno più tardi in Impostazioni → Server di gioco (o con il pulsante del server in Partita online).

## [0.28.2] - 2026-10-23

### Aggiunto
- Un nuovo set di immagini per Classic, “Dipinto semplice”: tutte le 534 carte come illustrazioni dipinte con pochissimi dettagli. Sceglilo in Giochi → Classic 2014 → Immagini delle carte (o nelle impostazioni).

## [0.28.1] - 2026-10-19

### Aggiunto
- Un nuovo set di immagini per Classic, “Cartone 2D”: tutte le 534 carte in uno stile da cartone animato piatto. Sceglilo in Giochi → Classic 2014 → Immagini delle carte (o nelle impostazioni).

## [0.28.0] - 2026-10-16

### Aggiunto
- Un nuovo gioco, Neonfall: cyberpunk nella sommersa Vesper Arc. Tre campioni (Iris Null, Mother Rust, Director Vale), 60 carte nuove, immagini, suoni, musica, font propri e uno stile neon. È il gioco predefinito del server.
- Una schermata «Giochi»: scegli il gioco, i set di immagini, suoni e musica, aggiungi un tuo gioco da un file .cardpack (anche nel browser), elimina quelli scaricati.
- Nel gioco diretto con i codici un amico può inviarti un gioco che non hai: consenso, trasferimento con avanzamento, verifica di integrità.
- Più server di gioco nelle impostazioni, ognuno con il suo accesso e i suoi amici. Accedere allo stesso account altrove chiude la sessione precedente («Hai effettuato l'accesso su un altro dispositivo»).
- Il server distribuisce i giochi: code, gradi e Arena per gioco; partita amichevole sul gioco di un amico, scaricato con consenso.
- Un controllo della firma Android: python3 tools/android_keystore_check.py apre una pagina che verifica i secret di GitHub e crea una nuova chiave.

### Modificato
- Il motore non sa più nulla di Hearthstone: tutto il gioco — regole, carte, la loro logica in un piccolo Lua, testi, immagini, suoni, gradi, timer — sta in un .cardpack. Classic 2014 è diventato un pacchetto così ed è stato verificato su 7833 partite registrate: i risultati coincidono bit per bit.
- Il protocollo del gioco diretto è la versione 3: le versioni precedenti non possono giocare con questa.

## [0.27.1] - 2026-10-15

### Corretto
- Le versioni per Windows e Linux si avviano di nuovo: il modulo delle regole ora viene distribuito accanto al gioco. Windows è uno .zip (ClassicHS.exe con il .dll accanto); l'AppImage lo contiene. Le immagini della documentazione non finiscono più nel gioco.

## [0.27.0] - 2026-10-15

### Aggiunto
- Server di gioco: una nuova lobby nello stile del gioco — scatole dei mazzi con gli eroi, un selettore Normale/Classificata, la medaglia del grado con le stelle, un grande pulsante Gioca; l'Arena con il biglietto, grandi ritratti degli eroi, il draft e la schermata della corsa fino a 12 vittorie.
- L'accesso al server viene ricordato: il gioco entra da solo all'avvio. Mentre sei connesso, ogni schermata ha un pulsante degli amici: chi è online, cerca o gioca, le richieste, finestre di chat sopra il gioco e inviti che puoi accettare ovunque.
- Un nuovo pannello di amministrazione del server: una dashboard dal vivo, un registro eventi con filtri (accessi, messaggi, mosse, errori), le partite con le mosse in tempo reale, gli account, le conversazioni; temi scuro e chiaro.

### Modificato
- Tutte le regole del gioco ora stanno in un solo modulo in Rust: gira nel gioco su ogni piattaforma (come WebAssembly nel browser) e sul server; la finestra del gioco disegna soltanto. Le regole sono state verificate su 7833 partite registrate: i risultati coincidono con il vecchio motore bit per bit.
- Partite tramite server: il server conduce la partita e invia a ciascuno solo ciò che può vedere — le carte nascoste dell'avversario non arrivano mai sul tuo computer. Il timer del turno gira sul server; dopo una caduta di connessione puoi rientrare nella partita.
- Gioco diretto con i codici: i due giochi controllano ogni mossa; se divergono, la partita finisce per entrambi con il messaggio “qualcosa non torna” (nessuno viene bannato). Le versioni precedenti non possono giocare con questa.

## [0.26.1] - 2026-10-15

### Corretto
- Nel gioco scaricato per Windows, macOS, Linux e Android, “Partita online” ora funziona: si può giocare tramite un server di gioco. Il gioco diretto con i codici resta solo nella versione per browser.

## [0.26.0] - 2026-10-15

### Aggiunto
- Un server di gioco (sperimentale, facoltativo): Partita online → “Tramite un server di gioco”. Un account con password, partite normali e classificate (i 25 gradi del 2014 e Leggenda, stelle, una nuova stagione ogni mese; un punteggio nascosto trova un avversario alla pari), l'Arena fino a 12 vittorie o 3 sconfitte, amici tramite tag, messaggi, inviti a una partita amichevole e blocco. Il server controlla ogni mossa con le regole del gioco stesso. L'indirizzo del server è in Impostazioni → “Server di gioco” (ws://localhost:7377 di default). Il server (Rust, cartella server/) non è ospitato da nessuna parte: lo avvii tu; ogni versione contiene il server per Windows, macOS e Linux. Il gioco diretto con i codici resta com'era.

## [0.25.1] - 2026-10-15

### Corretto
- I segreti dell'avversario compaiono in cima al suo ritratto, come i tuoi (prima, sotto).

## [0.25.0] - 2026-10-15

### Aggiunto
- Build per tutte le piattaforme: ogni versione ha una release su GitHub con il gioco per Windows (.exe), Linux (.AppImage), macOS (.zip), Android (.apk) e la versione web (.zip). Il sito ha il link: “Scarica il gioco”.

## [0.24.1] - 2026-10-12

### Modificato
- I mazzi base escono dagli elenchi dei mazzi: ogni classe ha un mazzo classico. Un mazzo base compare solo per una classe senza mazzo classico (ora nessuna). I mazzi base non modificati escono una volta dai mazzi salvati; quelli modificati restano.

## [0.24.0] - 2026-10-12

### Aggiunto
- Impostazioni → Set musicale: generata o libera (CC0) — musica da taverna medievale di RandomMind: “Minstrel Dance” nel menu, “The Old Tower Inn”, “King's Feast” e “The Bard's Tale” in partita. I suoni restano quelli generati.

## [0.23.3] - 2026-10-12

### Modificato
- Il mulligan come nell'originale: le carte scelte volano nel mazzo, le nuove prendono il loro posto e restano davanti a te (“In attesa dell'avversario…”); quando l'avversario ha scelto, al secondo giocatore appare la Moneta accanto, poi tutte le carte scendono in mano nello stesso ordine e solo dopo si pesca la carta del primo turno. La mano sotto la schermata del mulligan è nascosta.
- Il pulsante del tracker del mazzo sta sotto il pulsante del menu e non copre più i cristalli di mana dell'avversario.

## [0.23.2] - 2026-10-12

### Modificato
- Una carta con Combo giocabile in mano brilla di giallo invece che di verde quando in questo turno è già stata giocata una carta (la Combo funzionerà).
- La Moneta arriva sempre con la sua animazione — gira con una luce dorata e va in mano — anche quando l'avversario ha finito il mulligan più tardi, e per entrambi i giocatori.

## [0.23.1] - 2026-10-12

### Corretto
- Il pulsante che silenzia l'avversario mostra lo stato: “Muto”, e “Riattiva audio” finché l'avversario è silenziato.

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
