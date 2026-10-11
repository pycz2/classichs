# Änderungsprotokoll

Format: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Versionen: [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

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
