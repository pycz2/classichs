# Änderungsprotokoll

Format: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Versionen: [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.26.0] - 2026-10-15

### Hinzugefügt
- Ein Spielserver (experimentell, optional): Online-Spiel → „Über einen Spielserver“. Ein Konto mit Passwort, normale und Ranglistenspiele (die 25 Ränge von 2014 und Legende, Sterne, jeden Monat eine neue Saison; eine versteckte Wertung findet einen gleich starken Gegner), die Arena bis 12 Siege oder 3 Niederlagen, Freunde per Tag, Nachrichten, Einladungen zu einem Freundschaftsspiel und Blockieren. Der Server prüft jeden Zug mit den Regeln des Spiels selbst. Die Serveradresse steht unter Einstellungen → „Spielserver“ (standardmäßig ws://localhost:7377). Der Server selbst (Rust, Ordner server/) wird nirgends gehostet: Du startest ihn selbst; jedes Release enthält Server-Builds für Windows, macOS und Linux. Das direkte Spiel mit Codes bleibt, wie es war.

## [0.25.1] - 2026-10-15

### Behoben
- Die Geheimnisse des Gegners stehen oben auf seinem Porträt, wie deine (vorher darunter).

## [0.25.0] - 2026-10-15

### Hinzugefügt
- Builds für alle Plattformen: Jede Version bekommt ein GitHub-Release mit dem Spiel für Windows (.exe), Linux (.AppImage), macOS (.zip), Android (.apk) und der Webversion (.zip). Die Website verlinkt es: „Spiel herunterladen“.

## [0.24.1] - 2026-10-12

### Geändert
- Basis-Decks sind aus den Decklisten verschwunden: Jede Klasse hat ein klassisches Deck. Ein Basis-Deck erscheint nur für eine Klasse ohne klassisches Deck (zurzeit keine). Unveränderte Basis-Decks werden einmal aus den gespeicherten Decks entfernt; geänderte bleiben.

## [0.24.0] - 2026-10-12

### Hinzugefügt
- Einstellungen → Musiksatz: generiert oder offen (CC0) — mittelalterliche Tavernenmusik von RandomMind: „Minstrel Dance“ im Menü, „The Old Tower Inn“, „King's Feast“ und „The Bard's Tale“ im Spiel. Die Klänge bleiben die generierten.

## [0.23.3] - 2026-10-12

### Geändert
- Der Mulligan wie im Original: Die gewählten Karten fliegen ins Deck, die neuen auf ihre Plätze und bleiben vor dir („Warte auf den Gegner…“); hat der Gegner gewählt, erscheint beim zweiten Spieler daneben die Münze, dann gehen alle Karten in derselben Reihenfolge auf die Hand, und erst danach wird die Karte des ersten Zuges gezogen. Die Hand unter dem Mulligan ist verborgen.
- Der Knopf des Decktrackers sitzt unter dem Menüknopf und verdeckt die Manakristalle des Gegners nicht mehr.

## [0.23.2] - 2026-10-12

### Geändert
- Eine spielbare Karte mit Combo leuchtet gelb statt grün, sobald in diesem Zug schon eine Karte gespielt wurde (die Combo wirkt).
- Die Münze kommt immer mit ihrer eigenen Animation — sie dreht sich mit goldenem Licht herein und geht auf die Hand —, auch wenn der Gegner den Mulligan später beendet hat, und bei beiden Spielern.

## [0.23.1] - 2026-10-12

### Behoben
- Der Knopf zum Stummschalten des Gegners zeigt den Zustand: „Stummschalten“, und „Stummschaltung aufheben“, solange der Gegner stumm ist.

## [0.23.0] - 2026-10-12

### Geändert
- Mulligan: Nach „Bestätigen“ kommen die neuen Karten sofort auf die Hand, ohne auf den Gegner zu warten, und nehmen die Plätze der ersetzten ein — die Hand behält die Reihenfolge des Mulligan-Bildschirms; dann „Warte auf den Gegner…“. Online bleibt alles synchron: Das Mischen beim Mulligan nutzt den eigenen Zufallsstrom jedes Spielers.
- Der Online-Mulligan-Timer hat keine Lunte: In den letzten 10 Sekunden stehen rote Zahlen unter „Bestätigen“.
- Worauf der Gegner zeigt, löscht dein eigenes Leuchten nicht mehr: Grün oder Gelb bleibt, außen ein leichter roter Ring.
- Eine wegen voller Hand verbrannte Karte brennt nur mit dem Shader, ohne aufsteigende Dreiecke.

## [0.22.0] - 2026-10-12

### Hinzugefügt
- Eine Befehlsreihe: Den nächsten Zug kannst du geben, ohne auf die Animation des letzten zu warten — Karte ausspielen, angreifen, Heldenfähigkeit, Zug beenden. Befehle warten in einer Reihe (gelb markiert) und werden nach den Animationen nacheinander ausgeführt; ob ein Befehl möglich ist, wird nach den bereits vorgemerkten geprüft. Wird ein Befehl unmöglich (der Zug ist vorbei), wird die Reihe mit einem Hinweis abgebrochen. Im Tutorial gibt es keine Reihe.

### Geändert
- Die Lunte des Zuges brennt ohne die gepunktete Ascheline dahinter.

## [0.21.1] - 2026-10-12

### Geändert
- Online-Spiel: Alles, worauf der Gegner zeigt, leuchtet rot — Diener, Helden, Heldenfähigkeiten, Waffen, Geheimnisse und die angehobene Karte in seiner Hand (vorher nur Diener, in Weiß).

## [0.21.0] - 2026-10-12

### Hinzugefügt
- Arena-Regeln: Vor den Helden wählt der Gastgeber für beide „Ein Deck für die ganze Arena“ oder „Ein neues Deck für jedes Spiel“; für das zweite gibt es die Einstellung „Spieler dürfen ihr Deck behalten, statt neu zu wählen“. Ist sie an, wählt nach jedem Spiel jeder „Neues Deck bauen“ oder „Mein Deck behalten“, und der Gegner sieht, dass der Spieler entscheidet. Der Gast wartet auf die Wahl und sieht die Regeln; während einer neuen Auswahl ist der Punktestand zu sehen.

### Geändert
- Arena: Legendäre Karten kommen doppelt so oft (2 % bei einer normalen Wahl, 8 % bei Wahl 1, 10, 20 und 30), epische anderthalbmal so oft (7,5 % und 27 %).

## [0.20.1] - 2026-10-12

### Geändert
- Die Bilder zum Spielergebnis sind komprimiert: Der Download ist wieder etwa 61 MB groß (64 MB in 0.20.0).

## [0.20.0] - 2026-10-12

### Hinzugefügt
- Die Arena mit einem Freund online: Online-Spiel → Arena. Jeder nimmt einen von drei Helden und baut 30 Karten wie in der Arena von 2014: drei Karten einer Seltenheit pro Wahl (Basis und Gewöhnlich zählen als eine), selten oder besser bei Wahl 1, 10, 20 und 30, Klassenkarten anderthalbmal so häufig, beliebig viele Kopien. Rechts die Deckliste, unten links die Manakurve, oben rechts der Fortschritt des Gegners (Held gewählt oder nicht, Karten, bereit; nie der Held oder die Karten). Wenn beide „Bereit“ drücken, beginnt eine Serie bis drei Siege; nach jedem Spiel die Lobby mit dem Punktestand; die Arena kann jederzeit aufgegeben oder verlassen werden.
- Das Ergebnis eines Spiels aus deiner Sicht — Sieg!, Niederlage oder Unentschieden — über einem halbtransparenten Bild dazu (online stand vorher „Spieler N gewinnt“).

### Geprüft
- Unentschieden: Ein Höllenfeuer, das beide Helden tötet, ergibt ein Unentschieden, und beide Helden zerspringen.

## [0.19.5] - 2026-10-12

### Behoben
- Website: Der Abschnitt zum offenen Quellcode zeigte „{tests}“ statt der Zahl der Tests.

## [0.19.4] - 2026-10-12

### Hinzugefügt
- Ein Link zur Website in Telegram, WhatsApp, Discord, Slack und anderen Messengern zeigt eine Vorschau mit dem Haupt-Bildschirmfoto des Spiels (ein Spiel), Titel und Beschreibung.

## [0.19.3] - 2026-10-12

### Hinzugefügt
- Website: die Spielversion und ein Block „Was ist neu“ (die letzten Einträge des Änderungsprotokolls in der Seitensprache), ein Abschnitt „Im Spiel“, Fragen und Antworten (Voraussetzungen, Handys, wo Decks liegen, offline spielen, als App installieren, was das Online-Spiel sendet, Fehler melden), ein Abschnitt zum offenen Quellcode; der Link zum Änderungsprotokoll öffnet die Seitensprache; auf dem Handy scrollt die Seite nicht mehr seitwärts.

## [0.19.2] - 2026-10-12

### Geändert
- Website und README entsprechen jetzt dem Spiel: Training mit Wahl von Deck und Bot-Held, zehn bekannte Classic-Decks, das Relais fürs Online-Spiel, Debug-Werkzeuge in den Einstellungen, Emotes in den Worten der Helden, Kartenbild-Sätze und Kartenrücken; die Online-Schritte nutzen die Knopfnamen des Spiels; veraltete Aussagen sind entfernt (gar keine Server, alle Bilder per Code gezeichnet).

## [0.19.1] - 2026-10-12

### Geändert
- Website: neue Bildschirmfotos (Verlauf nach Zügen, Decktracker, Lektionen vor Missionen, Debug-Werkzeuge; die russische Seite zeigt russische Bilder), Texte für den heutigen Stand des Spiels und die Downloadgröße (etwa 61 MB). Auf dem Handy vergrößert ein Tippen eine Karte im Fächer, Doppeltippen dreht sie um.

## [0.19.0] - 2026-10-12

### Hinzugefügt
- Beim ersten Start fragt das Spiel nach der Sprache; die Sprache des Systems ist hervorgehoben.

## [0.18.5] - 2026-10-12

### Geändert
- Zufälliger Schaden an mehreren Zielen (Arkane Geschosse, Rachsüchtiger Zorn, Verrückter Bomber, Mehrfachschuss, Gespaltener Blitz usw.) fliegt Geschoss für Geschoss; die Lebenszahl des Ziels sinkt mit jedem Treffer.

## [0.18.4] - 2026-10-12

### Hinzugefügt
- Unangreifbar: der Diener ist von schimmerndem goldenem Dunst umhüllt, und das Wort hat sein Erklärfenster (Zauber und Heldenfähigkeiten können ihn nicht als Ziel wählen).

## [0.18.3] - 2026-10-12

### Hinzugefügt
- Verbrannte Karten (volle Hand) und Erschöpfungsschaden erscheinen im Verlauf links: eine eigene Kachel mit Bild und Erklärung beim Zeigen.

### Behoben
- Tutorial: Lehrensucher Cho kann nicht angegriffen werden, solange er Diener hat.

## [0.18.2] - 2026-10-12

### Geändert
- Die Sprachausgabe ist entfernt: das Spiel liest Namen und Emotes nicht mehr vor; die Einstellungen Stimme und Sprachausgabe sind weg. Sätze der Helden erscheinen als Text in Sprechblasen mit Spitze zum Helden.

### Behoben
- Ein angehaktes Feld verlor unter der Maus seinen Hintergrund.

## [0.18.1] - 2026-10-12

### Hinzugefügt
- Szeneneditor: Zonen für Geheimnisse und Waffe, die Wahl, wer zuerst am Zug ist, und Spielsteine in der Kartenliste.

## [0.18.0] - 2026-10-12

### Geändert
- Die Debug-Werkzeuge sind in die Einstellungen gezogen und ein Bildschirm mit Reitern: „Szene“ (eine Szene mit der Maus bauen: Helden, Mana, Schaden, Rüstung, Hand, Spielfeld, Deck; daneben das JSON; der Modus als Optionsfelder), „Interaktionstest“ (fertige Szenarien für jede der 534 Karten, 1108 insgesamt: Karte und Szenario wählen, und es läuft in einem echten Spiel mit allen Effekten und Klängen), „Kartentest“ und „Effekttest“.

## [0.17.1] - 2026-10-12

### Hinzugefügt
- Bei einer Niederlage zerspringt das Heldenporträt in Splitter.
- Blitz- und Giftzeichen stehen still und blitzen mit leisem Klang auf, wenn ihr Effekt auslöst.

### Behoben
- Tutorial: „Nächste Mission“ öffnet die Erklärungen als eigenen Bildschirm; der Belohnungsbildschirm blockiert nicht mehr.

## [0.17.0] - 2026-10-12

### Hinzugefügt
- Der Zugverlauf links ist nach Zügen getrennt („Zug N“ in der Farbe des Spielers); beim Zeigen auf einen Zug sieht man, was er bewirkte und bei wem: Schaden, Heilung, Stärkungen, Einfrieren, Stille, Tode, Herbeirufungen, angelegte Waffen sowie ausgelöste Kampfschreie und Todesröcheln. Verdeckte Karten des Gegners bleiben verdeckt.
- Der Decktracker hat einen eigenen Knopf neben dem Menü: „Dein Deck“ mit Kartenbildern, ×2, abgedunkelten verbrauchten Karten und der Ziehchance jeder Karte; „Vom Gegner gespielt“, eine wachsende Liste mit ×2.

## [0.16.2] - 2026-10-12

### Behoben
- Tutorial: nach einem Sieg öffnete „Nächste Mission“ die Erklärungen unter dem Belohnungsbildschirm, und der Bildschirm blockierte.

## [0.16.1] - 2026-10-12

### Hinzugefügt
- Unter „Zug beenden“: die Spielzeit und, im Online-Spiel, die verbleibende Zugzeit.
- Alles auf dem Tisch leuchtet unter der Maus; eine Waffe dreht sich um, wenn ihr Held nicht am Zug ist.
- Diener und Helden sprechen ihre Sätze (beim Ausspielen, Angriff, Tod, Emotes, zu Spielbeginn, beim Aufgeben), wenn es eine Aufnahme gibt; Helden-Emotes in eigenen Worten.

### Geändert
- Die Zündschnur des Timers ist eine gedrehte Schnur mit glühender Glut, Funken und Rauch.
- Eine verbrannte Karte brennt von den Rändern her mit glühender Kante weg.
- Ein Treffer am Helden: größere Schadenszahl; über 5 Schaden wackelt es stärker mit schwerem Klang.
- Ein Held, der angreifen kann, leuchtet heller.

## [0.16.0] - 2026-10-11

### Hinzugefügt
- Hauptmenü: Spielen öffnet ein Untermenü mit Online-Spiel, Training und Tutorial.
- Training in Schritten: ein Deck aus einer Liste mit Heldenporträts wählen (oder zu den Decks gehen), dann den Gegner aus einem 3×3-Raster, dann Spielen.
- Online-Spiel in Schritten: Name, Deck, Spiel erstellen oder beitreten; neben den Codes steht ein Kopieren-Knopf.
- Tutorial: Missionen mit den Porträts der Bosse; vor jeder Mission bebilderte Erklärungen der neuen Begriffe (Kartenteile, Kampf, Mana, Zauber, Kampfschrei, Spott, Ansturm, Todesröcheln, Heldenfähigkeit, Einfrieren, Waffen).
- Sammlung und Decks auf einem Bildschirm: links alle Karten mit Klassenreitern, Filtern nach Typ, Kosten, Seltenheit und Suche; rechts die Decks mit Kopieren, Exportieren und Löschen; ein Deck wird am selben Ort bearbeitet.

### Behoben
- Online-Spiel: ein TURN-Relais für Netze ohne direkten Weg; der Gast wartet bis zu 4 Minuten auf die Antwort des Gastgebers und erneuert die ganze Zeit die Verbindungskandidaten (vorher gab der Browser nach wenigen Sekunden auf).

## [0.15.3] - 2026-10-11

### Hinzugefügt
- Der Ladebildschirm zeigt die Version des Spiels.

## [0.15.2] - 2026-10-11

### Geändert
- Klassenembleme sind schlicht und flach; das Schwert am Angriffsstein ist kürzer, zeigt nach rechts oben, der Griff ist links unten zu sehen; der Blitz unter dem Porträt ist halb so groß; die Giftflasche ist grün, kleiner und ruhig.
- Stille: leuchtende rosa Bänder winden sich um das Porträt.
- Todesröcheln: das Schädelzeichen wächst aus dem Diener und steigt auf.
- Ein Diener mit Kampfschrei nimmt erst seinen Platz ein, dann geht der Pfeil zum Ziel von ihm aus; Rechtsklick oder der Pfeil zurück in die Hand bricht ab, die Karte kehrt auf die Hand zurück.

### Behoben
- Die Funken von Zauberschaden blieben manchmal stehen.

## [0.15.1] - 2026-10-11

### Geändert
- Die Steine für Mana, Leben, Angriff, Rüstung und Haltbarkeit sind kleiner und in der Mitte schlicht, damit die Zahlen besser lesbar sind; die Zeichen unter dem Porträt sind kleiner.

## [0.15.0] - 2026-10-11

### Hinzugefügt
- Gemalte Oberflächenbilder: Manakristall, Lebenstropfen, Angriffsstein mit Schwert, Rüstungs- und Haltbarkeitsschilde, Spott-Schild, Totenkopf mit Knochen, Giftflasche, Blitz, Klassenembleme, ein Bild für Erschöpfung.
- Giftige Diener (Kaiserkobra, Geduldige Attentäterin) tragen eine Giftflasche.
- Ein Schlüsselwort-Fenster für Wutanfall.
- Die Karte eines zum Schweigen gebrachten Dieners zeigt beim Zeigen ihren Text rot durchgestrichen.
- Überladung ist sofort sichtbar: orange Schlösser über den Kristallen für den nächsten Zug; ein gesperrter Kristall zeigt ein Schloss statt eines Kreuzes.
- Eine Karte, die eine Karte auf dem Tisch erschafft (Erzmagier Antonidas, Ysera), fliegt von ihr in die Hand.

### Geändert
- Das Leuchten (spielbar, gewählt, Ziel) liegt immer außerhalb aller Effekte einer Karte.
- Windzorn: Böen auf einer geneigten Bahn, hinter und vor der Karte.
- Verstohlenheit: ein Dunst, durch den das Bild schwach scheint; Eingefroren: eine Reifschicht und ein eisiger Rand.
- Geheimnisse am Heldenporträt sind rund: lila beim Magier, grün beim Jäger, gelb beim Paladin.
- Seltenheitssteine sind rund, mit Schatten und Glanzlicht.
- Der Drache eines legendären Dieners umfasst nur den oberen Teil des Ovals.

## [0.14.1] - 2026-10-11

### Geändert
- Der Drache eines legendären Dieners auf dem Tisch windet sich um das Oval des Porträts.

### Behoben
- Im Browser fügte das erste Cmd/Strg+V nichts statt des kopierten Codes ein (Code eines Freundes, Deckimport).
- Online-Spiel: die Zeit, in der ein Tab verborgen war, bricht das Warten auf die Verbindung nicht mehr ab.
- Eine Handkarte lässt sich unter der angehobenen Karte greifen, wo sie lag.
- Schlüsselwort-Fenster erscheinen wieder beim Zeigen auf eine Handkarte.

## [0.14.0] - 2026-10-11

### Hinzugefügt
- 10 fertige klassische Decks im Deckmenü: Control Warrior, Midrange Shaman, Midrange Druid, Control Priest, Miracle Rogue, Midrange Paladin, Handlock, Freeze Mage, Midrange Hunter, Zoolock. Spieler mit gespeicherten Decks erhalten sie einmal.

## [0.13.0] - 2026-10-11

### Hinzugefügt
- Mulligan: ersetzte Karten fliegen ins Deck, neue an ihre Plätze, die Münze dreht sich mit goldenem Licht herein, dann geht die ganze Hand nach unten. Zum Austausch markierte Karten tragen ein rotes Siegel mit weißem Kreuz.
- Erschöpfung: eine dunkle Karte mit Schädel und Schaden fliegt aus dem leeren Deck in den Helden.
- Eine verbrannte Karte (volle Hand) wird gezeigt und geht in Flammen auf.
- Zeigt die Maus auf ein Deck, sieht man auch die Kartenzahl auf der Hand dieses Spielers.

### Geändert
- Das Mana, das die Karte unter der Maus kosten würde, pulsiert deutlich, wenn es reicht.
- Das Leuchten spielbarer Karten und Schaltflächen ist schmaler und am Rand heller.

## [0.12.2] - 2026-10-11

### Geändert
- Spielbare Karten, Diener, die Heldenfähigkeit und die Schaltfläche „Zug beenden“ haben ein weiches, pulsierendes Leuchten statt eines Umrisses.

## [0.12.1] - 2026-10-11

### Hinzugefügt
- Zeigt die Maus auf eine Handkarte, blinken die Manakristalle, die sie kosten würde, wenn sie spielbar ist.

## [0.12.0] - 2026-10-11

### Hinzugefügt
- Effekte auf dem Tisch: Zauber, Kampfschreie, Todesröcheln und Effekte zu Beginn und Ende des Zuges schicken Geschosse von ihrer Quelle zu jedem Ziel. Beim Treffer zeigt jeder Diener und Held, was mit ihm geschah: eine Explosion bei Schaden, Funken bei Heilung, Pfeile bei Stärkung oder Schwächung, ein Aufblitzen bei einem neuen Schlüsselwort, Eis, einen Ring der Stille, Rauch beim Verwandeln, ein Portal beim Herbeirufen, einen Schädel beim Todesröcheln, ein Aufleuchten beim Kampfschrei, einen Wirbel bei Kontrollwechsel, einen Schild bei Rüstung.
- Geänderte Zahlen auf Karten wachsen kurz mit ihrem Stein.
- Das Volk einer Karte (Wildtier, Dämon, Drache, Murloc, Mech, Totem, Pirat, Untoter) auf einer Plakette unten auf der Karte.
- Ein immuner Diener leuchtet weiß, Funken drehen sich um ihn.

### Geändert
- Der Spott-Schild folgt dem Umriss des Porträts.
- „Ihr seid am Zug“ erscheint nach den Effekten am Zugende.

## [0.11.0] - 2026-10-11

### Hinzugefügt
- Sechs Kartenrücken zur Wahl in den Einstellungen: Klassisch, Horde, Druide, Arkan, Gold, Nacht.
- Effektlabor im Debug-Tisch: jede Karte auf dem Tisch und auf der Hand mit ihren kleinen Fenstern; Schlüsselwörter, Stärkungen, Schwächungen, Auren, Schaden, Stille, Schlaf, Kostenänderungen und Leuchten lassen sich in jeder der 8 Sprachen ein- und ausschalten.

### Geändert
- Der Tisch ändert sich im Moment des Treffers: Zahlen, Schilde und Tode erscheinen, wenn der Angreifer sein Ziel berührt oder das Geschoss des Zaubers ankommt, nicht vorher. Ein sterbender Diener verblasst mit seinen letzten Zahlen.

### Behoben
- In der Webversion stand über dem Menütitel ein weißes Rechteck statt des Drachen.
- Die Karten auf der Seite des Spiels zeichnet das Spiel selbst; sie sehen aus wie im Spiel.

## [0.10.0] - 2026-10-11

### Hinzugefügt
- Jede Karte hat jetzt ihr eigenes generiertes Bild.
- Der Kartentext ist für jede Karte in jeder Sprache von Hand gesetzt: Zeilen, Schriftgröße und Position. Eine Prüfung stellt sicher, dass kein Text über den Rahmen oder auf die Steine ragt; die Zeilen sind ausgewogen, Zahlen bleiben bei ihrem Wort, Schlüsselwörter werden nicht getrennt.
- Kartenlabor (im Debug-Tisch): eine Karte in allen 8 Sprachen zugleich mit ihren Rahmen und einer Liste der Probleme; Größen, Position und Zeilen lassen sich ändern und speichern.
- Diener zeigen ihre Änderungen in kleinen Fenstern: Stärkungen mit der Karte, die sie gab, Auren, gesetzte Werte, erhaltene Schlüsselwörter, Eingefroren, Zum Schweigen gebracht. Schlüsselwort-Fenster auch in der Sammlung und beim Deckbau.
- Legendäre Karten: ein gerader goldener Drachenfries entlang der Oberkante der Karte.
- Der Ladebildschirm im aktuellen Menü-Aussehen.

### Geändert
- Das Schwert hinter dem Angriffsstein ragt nach oben links über den Kartenrand hinaus, weg vom Text.
- Stärkerer Kontrast der Zahlen auf den Karten, vor allem bei gestärkten und beschädigten Werten.

### Behoben
- Der französische Text einiger Karten zeigte „|4(point,points)“ statt „point“ oder „points“.
- Auf der Seite des Spiels ist der letzte Buchstabe des Titels nicht mehr abgeschnitten.

## [0.9.0] - 2026-10-12

### Hinzugefügt
- Hauptmenü: ein generierter Tavernenhintergrund mit langsamem Zoom, fliegende Funken, ein goldener Vektortitel mit Drache und laufendem Glanzlicht, die Schaltflächen erscheinen nacheinander.
- Generierte Hintergründe: Das Match wird auf einem steinernen Spielfeld auf einem Tavernentisch gespielt, Deckauswahl und Sammlung befinden sich in einer Tavernenbibliothek, die übrigen Bildschirme in einer abgedunkelten Taverne.
- Schrift Alegreya für die Oberfläche (Lateinisch, Kyrillisch, Griechisch) und hölzerne Schaltflächen im Tavernenstil mit abgerundeten Ecken und goldenem Rahmen; abgerundete Eingabefelder, goldene Schieberegler.
- Kartentexte passen immer in den Rahmen: Die Schriftgröße wird für jede Karte in jeder Sprache durch Messen angepasst. Schlüsselwörter in Fettschrift.
- Erklärungsfelder zu Schlüsselwörtern neben der vergrößerten Karte.
- Ein Schwert hinter dem Angriffsstein, ein kompakter generierter Drache auf legendären Karten.
- Die Heldenfähigkeit dreht sich nach dem Einsatz um; die Schaltfläche „Zug beenden“ leuchtet grün, wenn keine Züge mehr möglich sind.
- Seltenheitsfilter in der Sammlung und beim Deckbau.
- Decklisten wie im Original: ein Streifen mit dem Heldenporträt hinter dem Decknamen, ein Streifen mit dem Kartenbild in der Kartenliste des Decks, die Kosten auf einem Kristall, die Deckfüllung als Balken.
- Das Änderungsprotokoll öffnet sich in der Sprache des Spiels.
- Das Spiel lässt sich als App installieren (PWA) und nach dem ersten Laden offline spielen.
- Auf der Spielseite sind die Screenshots auf Englisch.

### Behoben
- Wiederholte oder zu häufige Absichten des Gegners belasten das Spielfeld nicht mehr; die Pop-up-Karte des Verlaufs wird nicht bei jeder Mausbewegung neu erstellt; die Mulligan-Bestätigung weicht dem Timer und einem Verbindungsabbruch; eine gezogene Karte bleibt über dem Spielfeld.

## [0.8.1] - 2026-10-11

### Behoben (nach Review)
- Im Netzwerkspiel konnte der Timer einen neuen Zug selbst beenden, während die Animation des gegnerischen Zugs noch lief.
- Ein Rechtsklick während des Ziehens einer Karte bricht das Ziehen fehlerfrei ab.
- Handkarten werden nicht mehr über den Einstellungen, dem Menü, dem Mulligan und dem Spielende-Bildschirm gezeichnet.
- Ein auf die Hand zurückgeholter oder verwandelter Diener ändert sich an Ort und Stelle, statt zu „sterben“ und als neue Karte aus dem Deck zu erscheinen.

## [0.8.0] - 2026-10-11

### Hinzugefügt
- Spieltisch wie im Original: ovale Diener mit Angriffsstein und Lebenstropfen, steinerner Spott-Schild, goldener Drache über legendären Dienern, Kartenrahmen mit Namensband und Pergament, Heldenporträts im Bogen mit Klassenwappen.
- Animierte Effekte auf dem Tisch: Windzorn, Gottesschild, Verstohlenheit, Einfrieren, Schlaf, Auslöser, Todesröcheln, Auren, Raserei, Zauberschaden, Stille.
- Karten ziehen per Drag-and-drop: Die Karte folgt dem Cursor, Diener rücken für die Einfügestelle auseinander, gebogene Pfeile für Zauber, Angriffe und Heldenfähigkeit. Auswahl per Klick funktioniert weiterhin.
- Animationen: Karte aus dem Deck ziehen, Ausspielen (die Karte des Gegners dreht sich in der Mitte um), Flug von Zaubern, Angriff von Dienern und Helden, Heldenfähigkeit, Tod, Rückkehr auf die Hand, Mulligan, Aufdecken eines Geheimnisses, Banner „Du bist dran“, Sprüche mit „sprechendem“ Helden. Der Bot wartet das Ende der Animationen ab.
- Fächerförmige Hand: Die Karte unter dem Cursor hebt sich an und wird größer.
- Deck neben dem Helden: Dicke nach Kartenzahl, genaue Zahl beim Darüberfahren.
- Zahnrad-Menü oben rechts: Verlauf, Decktracker, Einstellungen, Aufgeben. Emotes per Rechtsklick auf den eigenen Helden, „Stummschalten“ auf dem gegnerischen Helden.
- Verlaufsleiste links: Bilder der gespielten Karten, beim Darüberfahren die Karte, per Klick der Textverlauf.
- Im Netzwerkspiel ist zu sehen, worauf der Gegner schaut: angehobene Karte in seiner Hand, sein roter Pfeil, Hervorhebung des Dieners.
- Kartenbilder: generierte Illustrationen (lokaler Codex), Originalgrafik (nur für das lokale Spiel) und eigene Sets – jeder Ordner in `art/`; Auswahl in den Einstellungen. Wo es kein Bild gibt, wird gezeichnete Grafik verwendet, für jede Karte eine eigene.
- Einstellung der Animationsgeschwindigkeit: von normal bis 4-fach schneller.
- Standarddeck für jeden Helden beim ersten Start.
- Klassensymbole in der Sammlung, bei der Auswahl von Held und Gegner; Kostenfilter als Manakristalle.
- Spielseite in 8 Sprachen, mit Kartenbildern, Heldenporträts, Kartenfächer, Funken und Zählern.

### Geändert
- Neue Musik im Taverne-Stil: gezupfte Laute und Harfe, Flöte, Pad, Bass, Tamburin und Shaker, Echo und Hall. Das Menü hat einen ruhigen Walzer, im Kampf laufen drei verschiedene Stücke von 60–90 Sekunden. Jedes Match beginnt mit einem anderen Stück als das letzte, nach dem Ende eines Stücks folgt das nächste.
- Manakristalle statt des Textes „Mana 3/5“.

## [0.7.0] - 2026-10-11

### Hinzugefügt
- Spielseite auf GitHub Pages: https://pycz2.github.io/classichs/ – animierter Kopfbereich, Funktionen, Screenshot-Galerie, Russisch und Englisch; das Spiel lässt sich direkt auf der Seite starten.
- `README.md` mit Screenshots, Funktionen, Build und Projektaufbau.
- `tools/build_site.sh`: Build der Website und Veröffentlichung im Branch `gh-pages`.

### Geändert
- Das Beispiel auf dem Debug-Tisch ist eine Schaufensterposition: Geheimnis, Waffe, Spott, legendäre Diener, volle Hand.
- Die russischen Sprüche des Bosses der ersten Mission verwenden den offiziellen Namen „Hogger“.

### Behoben
- Zeichen, die in der Schrift fehlen, wurden als Quadrate angezeigt: Die Symbole der Diener (Todesröcheln, Auslöser, Stille) sind jetzt Vektorgrafiken, der Pfeil ist ASCII. Ein Test prüft, dass die Schrift jedes Zeichen der Oberfläche und der Übersetzungen enthält.

## [0.6.0] - 2026-10-11

### Hinzugefügt
- Oberfläche in 8 Sprachen: English, Русский, Deutsch, Français, Español, Português (Brasil), Italiano, Polski. Standardsprache ist die Systemsprache; der Sprachwechsel in den Einstellungen wirkt sofort, ohne Neustart.
- Einstellungsbildschirm (aus dem Menü und aus dem Match): Sprache, Lautstärke von Musik, Geräuschen und Stimme, Sprachausgabe, Bildschirmwackeln, Vollbild, Spielername.
- Vektorgrafik für jede Karte, jeden Helden und jede Heldenfähigkeit: Motiv nach Name, Volk, Typ und Klasse (Feuer, Eis, Yeti, Schaf, Murloc, Waffe und andere).
- Geräusche für Ereignisse auf dem Tisch und zwei Melodien (Menü und Kampf); alle Geräusche sind synthetisiert, ohne externe Dateien.
- Sprachausgabe mit der Systemstimme in der Sprache der Oberfläche: Namen legendärer Diener und neuer Helden, Emotes, Sprüche der Tutorial-Bosse.
- Änderungsprotokoll: Ein Klick auf die Version in der Ecke des Menüs öffnet den gesamten Änderungsverlauf des Spiels.
- Decktracker im Match: das eigene Deck, verbleibende Karten mit der Wahrscheinlichkeit, jede als Nächste zu ziehen, vom Gegner gespielte Karten. Jede Ansicht lässt sich ausblenden; die Auswahl wird gespeichert.
- Zugtimer im Netzwerkspiel: 75 Sekunden, in den letzten 15 Sekunden brennt die Lunte; ist die Zeit abgelaufen, endet der Zug von selbst.

### Geändert
- Der Zugverlauf markiert den Zugbeginn anhand des Ereignisses, nicht anhand des Textes; das Verlaufspanel springt nicht nach unten, während der Spieler alte Einträge liest.
- Gründe für Desynchronisation und der Standard-Spielername werden übersetzt.

### Behoben
- Die Schaltfläche „Aufgeben“ wurde nach dem Spielende nicht zu „Menü“.

### Behoben (nach Review)
- Der Zugverlauf zeigt nach dem Öffnen neue Züge an.
- Der Sprachwechsel im Match ändert auch die Überschriften von Decktracker und Verlauf, den Namen des Bots und geöffnete Fenster.
- Lange Kartentexte ragen nicht mehr über den Rahmen hinaus.

## [0.5.0] - 2026-10-11

### Hinzugefügt
- Tutorial: sechs Missionen mit Jaina Prachtmeer wie im Original – Hogger, Millhaus Manasturm, Lehrensucher Cho, König Mukla, Hemet Nesingwary, Illidan Sturmgrimm.
- Hinweise Schritt für Schritt, Sprüche der Bosse, Regeln der ersten Missionen (man kann nicht verlieren, man kann den Zug nicht mit ungenutztem Mana oder Angriff beenden), die Heldenfähigkeit wird in der fünften Mission freigeschaltet.
- Karten der Tutorial-Bosse: Hogger ZERQUETSCHT!, Fass, Stampfen, Der Wille Muklas, Transzendenz, Flammen von Azzinoth, Flammenexplosion und andere.
- Belohnungsbildschirm nach dem Sieg; der Tutorial-Fortschritt wird gespeichert, abgeschlossene Missionen können erneut gespielt werden.

## [0.4.0] - 2026-10-11

### Hinzugefügt
- Netzwerkspiel im Browser ohne eigenen Server: WebRTC direkt zwischen den Browsern, öffentlicher STUN von Google. Der Gastgeber erstellt einen Einladungscode, der Gast antwortet mit einem Antwortcode; die Codes werden über einen beliebigen Messenger übertragen.
- Synchronisation des Matches: Beide Seiten prüfen den Spielzustand nach jedem Zug; bei Abweichung, falscher Spielversion oder Verbindungsabbruch wird eine verständliche Meldung angezeigt.
- Spielername (für den Gegner sichtbar), 6 Emotes und die Schaltfläche „Gegner stummschalten“.

### Behoben (nach Review)
- Den Mulligan im Netzwerkspiel wählen beide Spieler gleichzeitig.
- Zuverlässigere Verbindung über verschiedene Netzwerke: Das Spiel wartet, bis der Browser die externe Adresse findet; es gibt ein Verbindungs-Timeout mit Hinweis.
- Verständliche Meldungen: „Gegner hat das Spiel verlassen“, „andere Spielversion“, „unterschiedliche Kartendaten“, „Desynchronisation“.
- Emotes können nicht öfter als alle 1,5 Sekunden gesendet werden; „Stummschalten“ blendet ein angezeigtes Emote sofort aus.

## [0.3.0] - 2026-10-11

### Hinzugefügt
- Sammlung: alle 382 Karten, Seiten mit je 8 Karten, Klassen-Reiter, Kostenfilter, Suche, vergrößerte Karte beim Darüberfahren.
- Decks: unbegrenzte Anzahl, Erstellen, Bearbeiten, Kopieren, Löschen; Hearthstone-Regeln (30 Karten, 2 Kopien, 1 legendäre, nur eigene Klasse und neutrale Karten).
- Decks werden im Browser gespeichert und bleiben nach einem Neustart erhalten; eine beschädigte Datei geht nicht verloren, sondern wird in `decks.bad.json` abgelegt.
- Hearthstone-Deckcodes: Export im Classic-Format; Import von Codes der Formate Classic, Standard und Wild, auch von alten Decks aus den Jahren 2014–2016 mit Originalkarten und von aus dem Client kopiertem Text.
- Training: Auswahl des eigenen Decks; ein unvollständiges Deck lässt sich nicht starten.

### Behoben (nach Review)
- Der Fehler beim Importieren eines Codes wird im Importfenster angezeigt.
- Ein Deck mit einer verschwundenen Karte lässt sich öffnen und bearbeiten; der Spieler erfährt, wenn die Deckdatei beschädigt war (die Kopie wird gespeichert).
- Es werden Deckcodes mit anderen Heldenbildern (Magni, Medivh usw.) und Codes aus Text mit einer Überschrift in der ersten Zeile importiert.
- Das Deck wird nach jeder Änderung gespeichert, nicht nur über die Schaltfläche „Done“.

## [0.2.0] - 2026-10-11

### Hinzugefügt
- Hauptmenü, Klassenauswahl für das Training, Standarddecks der neun Klassen.
- Spieltisch: Helden, Heldenfähigkeiten, Waffen, Geheimnisse, Tische, Hände, Mana; Mulligan, Wähle eine Karte, Auswahl bei Fährtenlesen, Spielende-Bildschirm.
- Mausbedienung: Karte → Variante → Platz auf dem Tisch → Ziel; Angriff; Heldenfähigkeit; Tooltip mit vergrößerter Karte.
- Einfache Effekte: aufsteigende Zahlen für Schaden und Heilung, Schatten des gestorbenen Dieners, Bildschirmwackeln bei starkem Schaden.
- Bot für das Training: probiert Aktionen an einer Kopie des Spiels durch und wählt die beste.
- Zugverlauf während des Matches: alle Züge von Anfang an, ohne Längenbegrenzung; fremde gezogene Karten sind verborgen.
- Debug-Tisch: Szenario in JSON, Kartensuche und Hinzufügen auf die Hand, den Tisch oder ins Deck; Spiel gegen den Bot oder für beide Seiten; Schaltfläche „Position → JSON“.

### Behoben (nach Review)
- Ein Diener lässt sich zwischen andere setzen, indem man auf den benachbarten Diener klickt.
- Der Verlauf zeigt dem Gegner keine durch Fährtenlesen abgeworfenen Karten.
- Der Debug-Tisch meldet falsche Feldtypen im Szenario und startet kein fehlerhaftes Match.
- Das Aufgeben des Matches erfordert eine Bestätigung.
- Der Bot denkt in großen Positionen schneller.

### Behoben
- Ein Geheimnis gilt als Zauber: Manawyrm, Antonidas, Wilder Pyromant, Goblinauktionator, Violette Ausbilderin und Manasüchtige sehen es; Gegenzauber negiert ein Geheimnis.
- Dunkler Wahnsinn: Der gestohlene Diener kann angreifen, auch wenn er im letzten Zug seines Besitzers angegriffen hat.
- Fährtenlesen wirft keine Karten ab, die der Spieler nicht gesehen hat.
- Mulligan: Das Ergebnis hängt nicht von der Reihenfolge ab, in der die Spieler ihre Auswahl bestätigt haben (wichtig für das Netzwerkspiel).
- Aufgeben ist jederzeit möglich, auch im Zug des Gegners und während des Mulligans.
- Szenarien speichern die Kosten der Handkarten, den Zustand des Helden und den Zähler der gespielten Diener; ein Fehler im Szenario ergibt eine Meldung statt eines Absturzes.
- Lichtbrut hängt nicht von der Reihenfolge der Auren ab; Verhüllen entfernt nicht die eigene Verstohlenheit des Dieners; Schlangenfalle löst bei vollem Tisch nicht aus.
- Eine ungültige Aktion (zum Beispiel aus dem Netzwerk) wird abgelehnt, ohne den Zustand zu ändern.

## [0.1.0] - 2026-10-11

### Hinzugefügt
- Gerüst des Godot-4.7-Projekts und Test-Runner.
- Daten von 382 Sammelkarten im Classic-Format (Juni 2014), Spielmarken und Tutorial-Karten in 14 Sprachen.
- Engine: Match-Start, Mulligan, Die Münze, Zug, Mana, Überladung, Erschöpfung, Verbrennen von Karten, Auftauen von Eingefroren.
- Engine: vollständiger Matchverlauf (`history`) – jede Aktion und alle ihre Ereignisse von Matchbeginn an.
- Engine: Ausspielen von Karten, Kriegsschrei, Combo, Wähle eine Karte, Geheimnisse, Waffen, Angriffe, Spott, Verstohlenheit, Windzorn, Heldenfähigkeit, Liste der erlaubten Aktionen.
- Engine: Szenarien – Aufbau jeder Position aus JSON und Speichern der aktuellen Position in JSON (Grundlage des Debug-Tisches).
- Karten: Heldenfähigkeiten aller 9 Klassen, INFERNO!, Gedankenstachel, Gedankenzersplitterung, Die Münze.
- Karten: neutrale Basic (43).
- Karten: neutrale Classic COMMON (40).
- Karten: neutrale Classic RARE (36).
- Karten: neutrale Classic EPIC (11).
- Karten: neutrale legendäre, Belohnungs- und Promokarten (27) und ihre Spielmarken: Banane, Traumkarten, Power Chord, Gelbin Mekkadrills Erfindungen, Heiltotem.
- Karten: Druide (25) und Varianten von Wähle eine Karte.
- Karten: Jäger (25), Jägergeheimnisse, Fährtenlesen.
- Karten: Magier (25), Magiergeheimnisse.
- Karten: Paladin (25), Paladingeheimnisse.
- Karten: Priester (25).
- Karten: Schurke (25), Combo.
- Karten: Schamane (25), Überladung.
- Karten: Hexenmeister (25), Lord Jaraxxus.
- Karten: Krieger (25). Alle 382 Sammelkarten des Classic-Formats sind umgesetzt.
- Vollständigkeitsprüfung: Jede Karte mit Effekt hat einen Hook; 1000 zufällige Matches ohne Fehler; die Engine läuft im Web-Build, der Hash stimmt mit dem nativen überein.
