# Journal des modifications

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/). Versions : [SemVer](https://semver.org/lang/fr/).

## [Unreleased]

## [0.8.1] - 2026-10-11

### Corrigé (après relecture)
- En partie en ligne, le minuteur pouvait terminer lui-même le nouveau tour pendant que l'animation du tour de l'adversaire se jouait encore.
- Le clic droit pendant le glisser-déposer d'une carte l'annule sans erreur.
- Les cartes de la main ne sont plus dessinées par-dessus les paramètres, les menus, le mulligan et l'écran de fin de partie.
- Un serviteur renvoyé en main ou transformé change sur place, au lieu de « mourir » avec une nouvelle carte du deck.

## [0.8.0] - 2026-10-11

### Ajouté
- Un plateau fidèle à l'original : serviteurs ovales avec pierre d'attaque et goutte de vie, bouclier de pierre pour la provocation, dragon doré au-dessus des légendaires, cadres de cartes avec ruban de nom et parchemin, portraits de héros en arche avec l'emblème de la classe.
- Effets animés sur le plateau : furie des vents, bouclier divin, camouflage, gel, sommeil, déclencheurs, râle d'agonie, auras, enrager, dégâts de sorts, silence.
- Glisser-déposer des cartes : la carte suit le curseur, les serviteurs s'écartent pour faire place à l'insertion, flèches courbes pour les sorts, les attaques et le pouvoir héroïque. La sélection par clics fonctionne aussi.
- Animations : pioche depuis le deck, jeu d'une carte (la carte de l'adversaire se retourne au milieu), vol des sorts, attaque des serviteurs et du héros, pouvoir héroïque, mort, retour en main, mulligan, révélation d'un secret, bannière « À vous de jouer », répliques avec un héros qui « parle ». Le bot attend la fin des animations.
- Main en éventail : la carte sous le curseur se soulève et grossit.
- Deck près du héros : l'épaisseur dépend du nombre de cartes, le nombre exact s'affiche au survol.
- Menu en forme d'engrenage en haut à droite : historique, suivi du deck, paramètres, abandonner. Les émotes se font par clic droit sur son héros, « Ignorer » sur le héros de l'adversaire.
- Bande d'historique à gauche : images des cartes jouées, la carte s'affiche au survol, l'historique texte s'ouvre d'un clic.
- En partie en ligne, on voit où regarde l'adversaire : carte soulevée dans sa main, sa flèche rouge, serviteur surligné.
- Images des cartes : illustrations générées (Codex local), art original (en jeu local uniquement) et vos propres jeux d'images, n'importe quel dossier dans `art/` ; sélection dans les paramètres. Quand il n'y a pas d'image, un visuel dessiné, unique pour chaque carte.
- Réglage de la vitesse des animations : de normale à 4 fois plus rapide.
- Deck de base pour chaque héros au premier lancement.
- Icônes de classe dans la collection, le choix du héros et de l'adversaire ; les filtres de coût sont des cristaux de mana.
- Page du jeu en 8 langues, avec images de cartes, portraits de héros, main en éventail, étincelles et compteurs.

### Modifié
- Nouvelle musique dans l'esprit de la taverne : luth et harpe pincés, flûte, nappe, basse, tambourin et shaker, écho et réverbération. Menu : valse paisible ; en combat, trois morceaux différents de 60 à 90 secondes. Chaque match commence par un morceau différent du précédent, et le suivant joue à la fin du morceau.
- Cristaux de mana au lieu du texte « Mana 3/5 ».

## [0.7.0] - 2026-10-11

### Ajouté
- Page du jeu sur GitHub Pages : https://pycz2.github.io/classichs/ — bandeau animé, fonctionnalités, galerie de captures d'écran, russe et anglais ; le jeu se lance directement sur la page.
- `README.md` avec captures d'écran, fonctionnalités, compilation et structure du projet.
- `tools/build_site.sh` : compilation du site et publication dans la branche `gh-pages`.

### Modifié
- L'exemple sur la table de débogage est une position de vitrine : secret, arme, provocation, serviteurs légendaires, main pleine.
- Les répliques russes du boss de la première mission utilisent le nom officiel « Дробитель » (Lardeur).

### Corrigé
- Les caractères absents de la police s'affichaient sous forme de carrés : les icônes de serviteurs (râle d'agonie, déclencheur, silence) sont désormais vectorielles, la flèche est en ASCII. Un test vérifie que la police contient chaque caractère de l'interface et des traductions.

## [0.6.0] - 2026-10-11

### Ajouté
- Interface en 8 langues : English, Русский, Deutsch, Français, Español, Português (Brasil), Italiano, Polski. La langue par défaut est celle du système ; le changement de langue dans les paramètres est immédiat, sans redémarrage.
- Écran des paramètres (depuis le menu et depuis un match) : langue, volume de la musique, des sons et de la voix, doublage, tremblement de l'écran, plein écran, nom du joueur.
- Visuel vectoriel pour chaque carte, héros et pouvoir héroïque : motif selon le nom, la race, le type et la classe (feu, glace, yéti, mouton, murloc, arme, etc.).
- Sons des événements du plateau et deux mélodies (menu et combat) ; tous les sons sont synthétisés, sans fichiers externes.
- Doublage avec la voix du système dans la langue de l'interface : noms des serviteurs légendaires et des nouveaux héros, émotes, répliques des boss du tutoriel.
- Journal des modifications : un clic sur la version dans le coin du menu ouvre tout l'historique des modifications du jeu.
- Suivi du deck en match : son propre deck, cartes restantes avec la probabilité de piocher chacune ensuite, cartes jouées par l'adversaire. Chaque vue peut être masquée ; le choix est mémorisé.
- Minuteur de tour en partie en ligne : 75 secondes, la mèche brûle durant les 15 dernières secondes ; quand le temps est écoulé, le tour se termine tout seul.

### Modifié
- L'historique des tours marque le début d'un tour selon l'événement et non selon le texte ; le panneau d'historique ne saute plus en bas pendant que le joueur lit d'anciennes entrées.
- Les causes de désynchronisation et le nom de joueur par défaut sont traduits.

### Corrigé
- Le bouton « Abandonner » ne devenait pas « Menu » après la fin de la partie.

### Corrigé (après relecture)
- L'historique des tours affiche les nouveaux tours après son ouverture.
- Le changement de langue en match change aussi les titres du suivi du deck et de l'historique, le nom du bot et les fenêtres ouvertes.
- Les textes de cartes longs ne dépassent plus du cadre.

## [0.5.0] - 2026-10-11

### Ajouté
- Tutoriel : six missions avec Jaina, comme dans l'original — Lardeur, Milhouse Tempête-de-Mana, Chroniqueur Cho, Roi Mukla, Hemet Nesingwary, Illidan Hurlorage.
- Conseils étape par étape, répliques des boss, règles des premières missions (impossible de perdre, impossible de finir son tour avec du mana ou une attaque inutilisés), le pouvoir héroïque se débloque à la cinquième mission.
- Cartes des boss du tutoriel : Lardeur TOUT CASSER !, Tonneau, Piétinement, Volonté de Mukla, Transcendance, Flammes d'Azzinoth, Explosion de flammes et autres.
- Écran de récompense après la victoire ; la progression du tutoriel est sauvegardée, les missions terminées peuvent être rejouées.

## [0.4.0] - 2026-10-11

### Ajouté
- Partie en ligne dans le navigateur sans serveur dédié : WebRTC directement entre navigateurs, STUN public de Google. L'hôte crée un code d'invitation, l'invité répond avec un code de réponse ; les codes se transmettent par n'importe quelle messagerie.
- Synchronisation du match : les deux côtés vérifient l'état de la partie après chaque tour ; en cas de divergence, de mauvaise version du jeu ou de coupure de connexion, un message clair s'affiche.
- Nom du joueur (visible de l'adversaire), 6 émotes et un bouton « ignorer l'adversaire ».

### Corrigé (après relecture)
- En partie en ligne, les deux joueurs choisissent leur mulligan en même temps.
- Connexion plus fiable entre réseaux différents : le jeu attend que le navigateur trouve l'adresse externe ; un délai de connexion avec une indication est prévu.
- Messages clairs : « l'adversaire est parti », « autre version du jeu », « données de cartes différentes », « désynchronisation ».
- Les émotes ne peuvent pas être envoyées plus d'une fois toutes les 1,5 secondes ; « ignorer » masque immédiatement l'émote affichée.

## [0.3.0] - 2026-10-11

### Ajouté
- Collection : les 382 cartes, pages de 8 cartes, onglets de classes, filtre par coût, recherche, carte agrandie au survol.
- Decks : nombre illimité, création, modification, copie, suppression ; règles de Hearthstone (30 cartes, 2 exemplaires, 1 légendaire, uniquement sa classe et les neutres).
- Les decks sont enregistrés dans le navigateur et subsistent après un redémarrage ; un fichier endommagé n'est pas perdu mais mis de côté dans `decks.bad.json`.
- Codes de decks Hearthstone : export au format Classic ; import des codes des formats Classic, Standard et Libre, y compris les anciens decks de 2014-2016 avec les cartes d'origine, et du texte copié depuis le client.
- Entraînement : choix de son deck ; un deck incomplet ne peut pas être lancé.

### Corrigé (après relecture)
- L'erreur d'import d'un code s'affiche dans la fenêtre d'import.
- Un deck contenant une carte disparue s'ouvre et se modifie ; le joueur est informé si le fichier de decks était endommagé (une copie est conservée).
- Les codes de decks avec d'autres apparences de héros (Magni, Medivh, etc.) et les codes tirés d'un texte avec un titre sur la première ligne sont importés.
- Le deck est enregistré après chaque modification, et pas seulement avec le bouton « Done ».

## [0.2.0] - 2026-10-11

### Ajouté
- Menu principal, choix de la classe pour l'entraînement, decks de base des neuf classes.
- Plateau de jeu : héros, pouvoirs héroïques, armes, secrets, plateaux, mains, mana ; mulligan, Choix multiple, choix de Pistage, écran de fin de partie.
- Contrôle à la souris : carte → option → emplacement sur le plateau → cible ; attaque ; pouvoir héroïque ; infobulle avec carte agrandie.
- Effets simples : nombres flottants de dégâts et de soins, ombre du serviteur mort, tremblement de l'écran en cas de gros dégâts.
- Bot d'entraînement : essaie des actions sur une copie de la partie et choisit la meilleure.
- Historique des tours pendant le match : tous les tours depuis le début, sans limite de longueur ; les cartes piochées par l'adversaire sont masquées.
- Table de débogage : scénario en JSON, recherche d'une carte et ajout en main, sur le plateau ou dans le deck ; partie contre le bot ou pour les deux camps ; bouton « Position → JSON ».

### Corrigé (après relecture)
- On peut placer un serviteur entre d'autres en cliquant sur le serviteur voisin.
- L'historique ne montre pas à l'adversaire les cartes défaussées par Pistage.
- La table de débogage signale les types de champs erronés du scénario et ne lance pas un match cassé.
- L'abandon d'un match demande une confirmation.
- Le bot réfléchit plus vite dans les grandes positions.

### Corrigé
- Un secret est considéré comme un sort : Wyrm de mana, Antonidas, Pyromancien, Commissaire-priseur, Enseignante pourpre et Accro au mana le voient ; Contresort annule le secret.
- Folie de l'ombre : le serviteur volé peut attaquer même s'il a attaqué au tour précédent de son propriétaire.
- Pistage ne défausse pas les cartes que le joueur n'a pas vues.
- Mulligan : le résultat ne dépend pas de l'ordre dans lequel les joueurs ont confirmé leur choix (important pour la partie en ligne).
- On peut abandonner à tout moment, y compris pendant le tour de l'adversaire et pendant le mulligan.
- Les scénarios conservent le coût des cartes en main, l'état du héros et le compteur de serviteurs joués ; une erreur dans un scénario donne un message et non un plantage.
- Rejeton de Lumière ne dépend pas de l'ordre des auras ; Dissimuler ne retire pas la Discrétion propre au serviteur ; Piège à serpents ne se déclenche pas quand le plateau est plein.
- Une action incorrecte (par exemple venant du réseau) est rejetée sans modifier l'état.

## [0.1.0] - 2026-10-11

### Ajouté
- Squelette du projet Godot 4.7 et lanceur de tests.
- Données de 382 cartes collectionnables du format Classic (juin 2014), des jetons et des cartes du tutoriel en 14 langues.
- Moteur : début de match, mulligan, La pièce, tour, mana, Surcharge, Fatigue, brûlure de cartes, dégel de Gelé.
- Moteur : historique complet du match (`history`) — chaque action et tous ses événements depuis le début du match.
- Moteur : jeu des cartes, Cri de guerre, Combo, Choix multiple, secrets, armes, attaques, Provocation, Camouflage, Furie des vents, pouvoir héroïque, liste des actions légales.
- Moteur : scénarios — construction de n'importe quelle position à partir de JSON et sauvegarde de la position actuelle en JSON (base de la table de débogage).
- Cartes : pouvoirs héroïques des 9 classes, FEU D'ENFER !, Pointe mentale, Briser l'esprit, La pièce.
- Cartes : neutres Basic (43).
- Cartes : neutres Classic COMMON (40).
- Cartes : neutres Classic RARE (36).
- Cartes : neutres Classic EPIC (11).
- Cartes : neutres légendaires, de récompense et promo (27) et leurs jetons : Banane, cartes Dream, Power Chord, inventions de Gelbin, Totem de soins.
- Cartes : Druide (25) et variantes de Choix multiple.
- Cartes : Chasseur (25), secrets de chasseur, Pistage.
- Cartes : Mage (25), secrets de mage.
- Cartes : Paladin (25), secrets de paladin.
- Cartes : Prêtre (25).
- Cartes : Voleur (25), Combo.
- Cartes : Chaman (25), Surcharge.
- Cartes : Démoniste (25), Seigneur Jaraxxus.
- Cartes : Guerrier (25). Les 382 cartes collectionnables du format Classic sont implémentées.
- Contrôle d'exhaustivité : chaque carte avec un effet a un hook ; 1000 matchs aléatoires sans erreur ; le moteur fonctionne dans la build web, le hash correspond à la version native.
