# Dziennik zmian

Format: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Wersjonowanie: [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.22.0] - 2026-10-12

### Dodano
- Kolejka rozkazów: następny ruch można wydać bez czekania na koniec animacji poprzedniego — zagrać kartę, zaatakować, użyć mocy bohatera, zakończyć turę. Rozkazy czekają w kolejce (zaznaczone na żółto) i wykonują się po kolei po animacjach; to, czy rozkaz jest możliwy, sprawdza się po tych, które już czekają. Gdy rozkaz staje się niemożliwy (tura się skończyła), kolejka jest anulowana z podpowiedzią. W samouczku kolejki nie ma.

### Zmieniono
- Lont tury pali się bez kropkowanej linii popiołu za sobą.

## [0.21.1] - 2026-10-12

### Zmieniono
- Gra sieciowa: wszystko, na co wskazuje przeciwnik, świeci na czerwono — stronnicy, bohaterowie, moce bohatera, broń, sekrety i uniesiona karta w jego ręce (wcześniej tylko stronnicy, na biało).

## [0.21.0] - 2026-10-12

### Dodano
- Zasady Areny: przed bohaterami gospodarz wybiera dla obu „Jedna talia na całą Arenę” albo „Nowa talia na każdą grę”; druga opcja ma ustawienie „Gracze mogą zostawić swoją talię zamiast składać nową”. Gdy jest włączone, po każdej grze każdy wybiera „Złóż nową talię” albo „Zostaw moją talię”, a przeciwnik widzi, że gracz decyduje. Gość czeka na wybór i widzi zasady; w czasie nowego wyboru kart widać wynik.

### Zmieniono
- Arena: karty legendarne trafiają się dwa razy częściej (2 % w zwykłym wyborze, 8 % przy wyborach 1, 10, 20 i 30), epickie półtora raza częściej (7,5 % i 27 %).

## [0.20.1] - 2026-10-12

### Zmieniono
- Obrazy wyniku gry są skompresowane: pobieranie znów ma około 61 MB (64 MB w 0.20.0).

## [0.20.0] - 2026-10-12

### Dodano
- Arena ze znajomym w sieci: Gra sieciowa → Arena. Każdy bierze jednego z trzech bohaterów i składa 30 kart jak na Arenie z 2014 roku: trzy karty jednej rzadkości na wybór (podstawowe i zwykłe liczą się jako jedna), rzadka lub lepsza przy wyborach 1, 10, 20 i 30, karty klasowe półtora raza częściej, bez limitu kopii. Lista talii po prawej, krzywa many na dole po lewej, postępy przeciwnika u góry po prawej (czy wybrał bohatera, ile kart, czy gotowy; nigdy bohater ani karty). Gdy obaj naciśniecie „Gotowe”, zaczyna się seria do trzech zwycięstw; po każdej grze poczekalnia z wynikiem; Arenę można poddać albo wyjść do menu na każdym etapie.
- Wynik gry z twojej strony — Zwycięstwo!, Porażka albo Remis — na półprzezroczystym obrazie (w grze sieciowej było „Gracz N wygrywa”).

### Sprawdzono
- Remis: Piekielny ogień, który zabija obu bohaterów, daje remis, a obaj bohaterowie rozpadają się na odłamki.

## [0.19.5] - 2026-10-12

### Naprawiono
- Strona: sekcja o otwartym kodzie pokazywała „{tests}” zamiast liczby testów.

## [0.19.4] - 2026-10-12

### Dodano
- Link do strony w Telegramie, WhatsAppie, Discordzie, Slacku i innych komunikatorach pokazuje podgląd z głównym zrzutem ekranu gry (rozgrywka), tytułem i opisem.

## [0.19.3] - 2026-10-12

### Dodano
- Strona: wersja gry i blok „Co nowego” (ostatnie wpisy dziennika zmian w języku strony), sekcja „W grze”, pytania i odpowiedzi (wymagania, telefony, gdzie są zapisane talie, gra offline, instalacja jako aplikacji, co wysyła gra sieciowa, jak zgłosić błąd), sekcja o otwartym kodzie; link do dziennika zmian otwiera język strony; na telefonie strona nie przewija się już w bok.

## [0.19.2] - 2026-10-12

### Zmieniono
- Strona i README zgadzają się z grą: trening z wyborem talii i bohatera bota, dziesięć znanych talii Classic, przekaźnik gry sieciowej, narzędzia debugowania w ustawieniach, emotki słowami bohaterów, zestawy grafik kart i rewersy; kroki gry sieciowej używają nazw przycisków z gry; usunięto nieaktualne twierdzenia (zero serwerów, cała grafika rysowana kodem).

## [0.19.1] - 2026-10-12

### Zmieniono
- Strona: nowe zrzuty ekranu (historia według tur, śledzenie talii, lekcje przed misjami, narzędzia debugowania; rosyjska strona pokazuje rosyjskie zrzuty), aktualne teksty i rozmiar pobierania (około 61 MB). Na telefonie dotknięcie powiększa kartę w wachlarzu, a podwójne dotknięcie ją odwraca.

## [0.19.0] - 2026-10-12

### Dodano
- Przy pierwszym uruchomieniu gra prosi o wybór języka; język systemu jest podświetlony.

## [0.18.5] - 2026-10-12

### Zmieniono
- Losowe obrażenia w kilka celów (Arkane Pociski, Gniew Mściciela, Szalony Bombardier, Salwa, Rozwidlona Błyskawica itd.) lecą pocisk po pocisku; zdrowie celu spada z każdym trafieniem.

## [0.18.4] - 2026-10-12

### Dodano
- Nieuchwytność: stronnik jest otoczony mieniącą się złotą mgiełką, a słowo ma swoje okienko (zaklęcia i moce specjalne nie mogą go wybrać na cel).

## [0.18.3] - 2026-10-12

### Dodano
- Spalone karty (pełna ręka) i obrażenia od zmęczenia widać w historii po lewej: własny kafelek z obrazkiem i opisem po najechaniu.

### Naprawiono
- Samouczek: Kronikarza Cho nie można atakować, dopóki ma stronników.

## [0.18.2] - 2026-10-12

### Zmieniono
- Usunięto syntezę mowy: gra nie czyta już na głos imion i emotek; ustawienia Głos i Mowa zniknęły. Kwestie bohaterów pokazują się jako tekst w dymkach z ogonkiem wskazującym bohatera.

### Naprawiono
- Zaznaczone pole traciło tło pod kursorem.

## [0.18.1] - 2026-10-12

### Dodano
- Edytor sceny: strefy Sekrety i Broń, wybór, kto zaczyna, oraz żetony na liście kart.

## [0.18.0] - 2026-10-12

### Zmieniono
- Narzędzia debugowania przeniesiono do ustawień; to jeden ekran z zakładkami: „Scena” (budowanie sceny myszą: bohaterowie, mana, obrażenia, pancerz, ręka, stół, talia; obok JSON; tryb jako przyciski opcji), „Test interakcji” (gotowe scenariusze dla każdej z 534 kart, razem 1108: wybierz kartę i scenariusz, a rozegra się w prawdziwej grze ze wszystkimi efektami i dźwiękami), „Test kart” i „Test efektów”.

## [0.17.1] - 2026-10-12

### Dodano
- Po porażce portret bohatera rozpryskuje się na odłamki.
- Znaczki błyskawicy i trucizny są nieruchome i błyskają z lekkim dźwiękiem, gdy efekt się uruchamia.

### Naprawiono
- Samouczek: „Następna misja” otwiera objaśnienia na osobnym ekranie; ekran nagrody już nie blokuje.

## [0.17.0] - 2026-10-12

### Dodano
- Historia ruchów po lewej jest podzielona na tury („Tura N” w kolorze gracza); po najechaniu na ruch widać, co zrobił i komu: obrażenia, leczenie, wzmocnienia, zamrożenie, wyciszenie, śmierci, przyzwania, założoną broń oraz wywołane okrzyki bojowe i ostatnie tchnienia. Ukryte karty przeciwnika pozostają ukryte.
- Śledzenie talii ma własny przycisk obok menu: „Twoja talia” z obrazkami, ×2, przyciemnionymi zużytymi kartami i szansą dobrania każdej karty; „Zagrane przez przeciwnika”, rosnąca lista z ×2.

## [0.16.2] - 2026-10-12

### Naprawiono
- Samouczek: po wygranej „Następna misja” otwierała objaśnienia pod ekranem nagrody i ekran się blokował.

## [0.16.1] - 2026-10-12

### Dodano
- Pod przyciskiem „Koniec tury”: czas gry i, w grze sieciowej, czas pozostały do końca tury.
- Wszystko na stole podświetla się pod kursorem; broń odwraca się, gdy to nie tura jej bohatera.
- Stronnicy i bohaterowie mówią swoje kwestie (przy zagraniu, ataku, śmierci, emotkach, na początku gry, przy poddaniu), gdy jest nagranie; emotki bohaterów ich własnymi słowami.

### Zmieniono
- Lont timera to skręcony sznur z żarzącym się węgielkiem, iskrami i dymem.
- Spalona karta wypala się od krawędzi z żarzącym się brzegiem.
- Uderzenie w bohatera: większa liczba obrażeń; ponad 5 obrażeń mocniej trzęsie z ciężkim dźwiękiem.
- Bohater, który może atakować, świeci jaśniej.

## [0.16.0] - 2026-10-11

### Dodano
- Menu główne: Graj otwiera podmenu z grą sieciową, treningiem i samouczkiem.
- Trening krok po kroku: wybór talii z listy z portretami bohaterów (lub przejście do talii), potem przeciwnik z siatki 3×3, potem Graj.
- Gra sieciowa krok po kroku: imię, talia, Utwórz grę lub Dołącz; kody mają obok przycisk Kopiuj.
- Samouczek: misje z portretami bossów; przed każdą misją ilustrowane objaśnienia nowych pojęć (części karty, walka, mana, zaklęcia, okrzyk bojowy, prowokacja, szarża, ostatnie tchnienie, moc specjalna, zamrożenie, broń).
- Kolekcja i talie na jednym ekranie: po lewej wszystkie karty z zakładkami klas, filtrami typu, kosztu, rzadkości i wyszukiwaniem; po prawej talie z kopiowaniem, eksportem i usuwaniem; talię edytuje się w tym samym miejscu.

### Naprawiono
- Gra sieciowa: przekaźnik TURN dla sieci bez bezpośredniej drogi; gość czeka do 4 minut na odpowiedź gospodarza i przez cały ten czas odnawia kandydatów połączenia (wcześniej przeglądarka poddawała się po kilku sekundach).

## [0.15.3] - 2026-10-11

### Dodano
- Ekran ładowania pokazuje wersję gry.

## [0.15.2] - 2026-10-11

### Zmieniono
- Emblematy klas są proste i płaskie; miecz przy kamieniu ataku jest krótszy, wskazuje w prawo w górę, rękojeść widać w lewym dole; błyskawica pod portretem jest o połowę mniejsza; fiolka trucizny jest zielona, mniejsza i nieruchoma.
- Wyciszenie: świecące różowe wstęgi owijają portret.
- Ostatnie tchnienie: znaczek czaszki rośnie ze stronnika i unosi się.
- Stronnik z okrzykiem bojowym najpierw zajmuje swoje miejsce, potem strzałka do celu wychodzi od niego; prawy przycisk myszy lub strzałka z powrotem do ręki anuluje, a karta wraca do ręki.

### Naprawiono
- Iskry obrażeń od zaklęć czasem się zatrzymywały.

## [0.15.1] - 2026-10-11

### Zmieniono
- Kamienie many, zdrowia, ataku, pancerza i wytrzymałości są mniejsze i gładkie w środku, by liczby były czytelniejsze; znaczki pod portretem są mniejsze.

## [0.15.0] - 2026-10-11

### Dodano
- Malowane obrazki interfejsu: kryształ many, kropla zdrowia, kamień ataku z mieczem, tarcze pancerza i wytrzymałości, tarcza prowokacji, czaszka ze skrzyżowanymi kośćmi, fiolka trucizny, błyskawica, emblematy klas, obrazek zmęczenia.
- Jadowici stronnicy (Kobra cesarska, Cierpliwa zabójczyni) mają fiolkę trucizny.
- Okienko słowa kluczowego dla Szału.
- Karta wyciszonego stronnika po najechaniu pokazuje tekst przekreślony czerwonym krzyżykiem.
- Przeciążenie widać od razu: pomarańczowe kłódki nad kryształami na następną turę; zablokowany kryształ pokazuje kłódkę zamiast krzyżyka.
- Karta stworzona przez kartę na stole (Arcymag Antonidas, Ysera) leci od niej do ręki.

### Zmieniono
- Poświaty (do zagrania, wybrane, cel) są zawsze na zewnątrz wszystkich efektów karty.
- Furia wichru: podmuchy na pochylonej orbicie, za kartą i przed nią.
- Ukrycie: mgiełka, przez którą lekko widać obrazek; Zamrożenie: warstwa szronu i lodowa krawędź.
- Sekrety na portrecie bohatera są okrągłe: fioletowe u maga, zielone u łowcy, żółte u paladyna.
- Kamienie rzadkości są okrągłe, z cieniem i odblaskiem.
- Smok legendarnego stronnika obejmuje tylko górną część owalu.

## [0.14.1] - 2026-10-11

### Zmieniono
- Smok legendarnego stronnika na stole owija się wokół owalu portretu.

### Naprawiono
- W przeglądarce pierwsze Cmd/Ctrl+V nie wklejało nic zamiast skopiowanego kodu (kod znajomego, import talii).
- Gra sieciowa: czas ukrycia karty przeglądarki nie przerywa już czekania na połączenie.
- Kartę w ręce można chwycić, klikając pod podniesioną kartą, tam gdzie leżała.
- Okienka słów kluczowych znów pojawiają się po najechaniu na kartę w ręce.

## [0.14.0] - 2026-10-11

### Dodano
- 10 gotowych klasycznych talii w menu talii: Control Warrior, Midrange Shaman, Midrange Druid, Control Priest, Miracle Rogue, Midrange Paladin, Handlock, Freeze Mage, Midrange Hunter, Zoolock. Gracze z zapisanymi taliami dostają je raz.

## [0.13.0] - 2026-10-11

### Dodano
- Mulligan: wymienione karty lecą do talii, nowe na ich miejsca, moneta pojawia się, obracając się w złotym blasku, a potem cała ręka zjeżdża w dół. Karty do wymiany mają czerwoną pieczęć z białym krzyżykiem.
- Zmęczenie: ciemna karta z czaszką i obrażeniami leci z pustej talii do bohatera.
- Spalona karta (pełna ręka) pokazuje się i płonie.
- Po najechaniu na talię widać też liczbę kart w ręce tego gracza.

### Zmieniono
- Mana, którą zużyłaby karta pod kursorem, wyraźnie pulsuje, jeśli jej starcza.
- Poświata kart i przycisków do zagrania jest węższa i jaśniejsza przy krawędzi.

## [0.12.2] - 2026-10-11

### Zmieniono
- Karty do zagrania, stronnicy, moc specjalna i przycisk „Koniec tury” mają miękką, pulsującą poświatę zamiast obwódki.

## [0.12.1] - 2026-10-11

### Dodano
- Po najechaniu na kartę w ręce migają kryształy many, które by zużyła, jeśli można ją zagrać.

## [0.12.0] - 2026-10-11

### Dodano
- Efekty na stole: zaklęcia, okrzyki bojowe, ostatnie tchnienia i efekty początku oraz końca tury wysyłają pociski ze źródła do każdego celu. W chwili trafienia każdy stronnik i bohater pokazuje, co się stało: wybuch przy obrażeniach, iskry przy leczeniu, strzałki przy wzmocnieniu i osłabieniu, błysk nowego słowa kluczowego, lód, pierścień wyciszenia, dym przemiany, portal przyzwania, czaszkę ostatniego tchnienia, rozbłysk okrzyku bojowego, wir przejęcia kontroli, tarczę pancerza.
- Zmienione liczby na kartach na chwilę rosną razem ze swoim kamieniem.
- Rasa karty (Bestia, Demon, Smok, Murlok, Mech, Totem, Pirat, Nieumarły) na tabliczce na dole karty.
- Niewrażliwy stronnik świeci na biało, wokół niego krążą iskry.

### Zmieniono
- Tarcza prowokacji biegnie wzdłuż konturu portretu.
- „Twoja tura” pojawia się po efektach końca tury.

## [0.11.0] - 2026-10-11

### Dodano
- Sześć rewersów kart do wyboru w ustawieniach: Klasyczny, Horda, Druid, Arkana, Złoty, Noc.
- Laboratorium efektów w stole debugowania: dowolna karta na stole i w ręce z okienkami; słowa kluczowe, wzmocnienia, osłabienia, aury, obrażenia, wyciszenie, sen, zmiany kosztu i podświetlenia można włączać i wyłączać w każdym z 8 języków.

### Zmieniono
- Stół zmienia się w chwili uderzenia: liczby, tarcze i śmierć widać, gdy atakujący dotyka celu lub pocisk zaklęcia dolatuje, nie wcześniej. Ginący stronnik znika ze swoimi ostatnimi liczbami.

### Naprawiono
- W wersji przeglądarkowej nad tytułem menu był biały prostokąt zamiast smoka.
- Karty na stronie gry rysuje sama gra; wyglądają tak jak w grze.

## [0.10.0] - 2026-10-11

### Dodano
- Każda karta ma teraz własny wygenerowany obrazek.
- Tekst kart jest złożony ręcznie dla każdej karty w każdym języku: wiersze, rozmiar czcionki i położenie. Sprawdzanie pilnuje, by żaden tekst nie wychodził poza ramkę ani nie wchodził na kamienie; wiersze są wyrównane, liczby zostają przy swoich słowach, słowa kluczowe nie są dzielone.
- Laboratorium kart (w stole debugowania): jedna karta naraz we wszystkich 8 językach, z ramkami i listą problemów; rozmiary, położenie i wiersze można zmieniać i zapisywać.
- Stronnicy pokazują swoje zmiany w okienkach: wzmocnienia z kartą, która je dała, aury, ustawione wartości, zdobyte słowa kluczowe, Zamrożenie, Wyciszenie. Okienka słów kluczowych także w kolekcji i przy budowaniu talii.
- Karty legendarne: prosty złoty fryz ze smokiem wzdłuż górnej krawędzi karty.
- Ekran ładowania w obecnym wyglądzie menu.

### Zmieniono
- Miecz za kamieniem ataku wystaje w lewo do góry, poza krawędź karty, z dala od tekstu.
- Mocniejszy kontrast liczb na kartach, zwłaszcza wzmocnionych i uszkodzonych wartości.

### Naprawiono
- Francuski tekst niektórych kart pokazywał „|4(point,points)” zamiast „point” lub „points”.
- Na stronie gry ostatnia litera tytułu nie jest już ucięta.

## [0.9.0] - 2026-10-12

### Dodano
- Menu główne: wygenerowane tło karczmy z powolnym przybliżaniem, lecące iskry, wektorowy złoty tytuł ze smokiem i przesuwającym się blaskiem; przyciski pojawiają się jeden po drugim.
- Wygenerowane tła: mecz toczy się na kamiennej planszy na stole w karczmie, wybór talii i kolekcja znajdują się w karczmianej bibliotece, pozostałe ekrany w przyciemnionej karczmie.
- Czcionka Alegreya w interfejsie (łacina, cyrylica, greka) i drewniane przyciski w stylu karczmy z zaokrąglonymi rogami i złotą ramką; zaokrąglone pola wprowadzania, złote suwaki.
- Teksty kart zawsze mieszczą się w ramce: rozmiar czcionki jest dobierany pomiarem dla każdej karty w każdym języku. Słowa kluczowe pogrubione.
- Okienka z objaśnieniem słów kluczowych obok powiększonej karty.
- Miecz za kamieniem ataku, mały wygenerowany smok na kartach legendarnych.
- Moc bohatera obraca się po użyciu; przycisk „Koniec tury” świeci na zielono, gdy nie ma już ruchów.
- Filtr rzadkości w kolekcji i przy budowaniu talii.
- Listy talii jak w oryginale: pasek z portretem bohatera za nazwą talii, pasek z grafiką karty na liście kart talii, koszt na krysztale, wypełnienie talii jako pasek.
- Dziennik zmian otwiera się w języku gry.
- Grę można zainstalować jako aplikację (PWA) i grać w nią offline po pierwszym załadowaniu.
- Na stronie gry zrzuty ekranu są po angielsku.

### Naprawiono
- Powtarzające się lub zbyt częste zamiary przeciwnika nie obciążają już stołu; wyskakująca karta historii nie jest tworzona na nowo przy każdym ruchu myszy; potwierdzenie mulligana ustępuje timerowi i utracie połączenia; przeciągana karta pozostaje nad stołem.

## [0.8.1] - 2026-10-11

### Naprawiono (po przeglądzie)
- W grze sieciowej zegar mógł sam zakończyć nową turę, gdy jeszcze odtwarzała się animacja tury przeciwnika.
- Kliknięcie prawym przyciskiem podczas przeciągania karty anuluje je bez błędów.
- Karty z ręki nie są już rysowane nad ustawieniami, menu, mulliganem i ekranem końca gry.
- Stwór zwrócony na rękę lub przemieniony zmienia się w miejscu, zamiast „umierać” i pojawiać się jako nowa karta z talii.

## [0.8.0] - 2026-10-11

### Dodano
- Stół jak w oryginale: owalne stwory z kamieniem ataku i kroplą zdrowia, kamienna tarcza prowokacji, złoty smok nad legendarnymi, ramki kart z wstęgą nazwy i pergaminem, łukowe portrety bohaterów z herbem klasy.
- Animowane efekty na stole: szał wichru, boska tarcza, ukrycie, zamrożenie, sen, wyzwalacze, agonia, aury, wściekłość, obrażenia od zaklęć, wyciszenie.
- Przeciąganie kart: karta podąża za kursorem, stwory rozsuwają się w miejscu wstawienia, zakrzywione strzałki dla zaklęć, ataków i mocy bohatera. Wybór kliknięciami też działa.
- Animacje: dobieranie karty z talii, zagrywanie (karta przeciwnika obraca się w połowie drogi), lot zaklęć, atak stworów i bohatera, moc bohatera, śmierć, powrót na rękę, mulligan, ujawnienie sekretu, baner „Twoja tura”, kwestie z „mówiącym” bohaterem. Bot czeka na koniec animacji.
- Ręka w wachlarzu: karta pod kursorem unosi się i powiększa.
- Talia przy bohaterze: grubość zależy od liczby kart, dokładna liczba po najechaniu kursorem.
- Menu w kształcie koła zębatego w prawym górnym rogu: historia, deck tracker, ustawienia, poddanie się. Emocje — prawym przyciskiem na własnym bohaterze, „Wycisz” — na bohaterze przeciwnika.
- Pasek historii po lewej: obrazki zagranych kart, po najechaniu — karta, po kliknięciu — historia tekstowa.
- W grze sieciowej widać, gdzie patrzy przeciwnik: uniesiona karta w jego ręce, jego czerwona strzałka, podświetlenie stwora.
- Obrazy kart: wygenerowane ilustracje (lokalny Codex), oryginalna grafika (tylko do gry lokalnej) i własne zestawy — dowolny folder w `art/`; wybór w ustawieniach. Tam, gdzie nie ma obrazka, jest rysowana grafika, osobna dla każdej karty.
- Ustawienie szybkości animacji: od normalnej do 4 razy szybszej.
- Podstawowa talia dla każdego bohatera przy pierwszym uruchomieniu.
- Ikony klas w kolekcji, wyborze bohatera i przeciwnika; filtry kosztu — kryształy many.
- Strona gry w 8 językach, z obrazkami kart, portretami bohaterów, wachlarzem kart, iskrami i licznikami.

### Zmieniono
- Nowa muzyka w duchu karczmy: szarpane lutnia i harfa, flet, pad, bas, tamburyn i shaker, echo i pogłos. Menu — spokojny walc, w walce trzy różne utwory po 60–90 sekund. Każdy mecz zaczyna się od utworu innego niż poprzednio, po zakończeniu utworu gra następny.
- Kryształy many zamiast tekstu „Mana 3/5”.

## [0.7.0] - 2026-10-11

### Dodano
- Strona gry na GitHub Pages: https://pycz2.github.io/classichs/ — animowany nagłówek, funkcje, galeria zrzutów ekranu, rosyjski i angielski; grę można uruchomić bezpośrednio na stronie.
- `README.md` ze zrzutami ekranu, funkcjami, budowaniem i budową projektu.
- `tools/build_site.sh`: budowanie strony i publikacja w gałęzi `gh-pages`.

### Zmieniono
- Przykład na stole debugowania to pozycja pokazowa: sekret, broń, prowokacja, legendarne stwory, pełna ręka.
- Rosyjskie kwestie bossa pierwszej misji używają oficjalnego imienia „Wyżer”.

### Naprawiono
- Znaki, których nie ma w czcionce, wyświetlały się jako kwadraty: ikony stworów (agonia, wyzwalacz, wyciszenie) są teraz wektorowe, strzałka — ASCII. Test sprawdza, że czcionka zawiera każdy znak interfejsu i tłumaczeń.

## [0.6.0] - 2026-10-11

### Dodano
- Interfejs w 8 językach: English, Русский, Deutsch, Français, Español, Português (Brasil), Italiano, Polski. Domyślnie język systemu; zmiana języka w ustawieniach następuje od razu, bez restartu.
- Ekran ustawień (z menu i z meczu): język, głośność muzyki, dźwięków i głosu, lektor, drżenie ekranu, pełny ekran, nazwa gracza.
- Wektorowa grafika dla każdej karty, bohatera i mocy bohatera: motyw według nazwy, rasy, typu i klasy (ogień, lód, yeti, owca, murloc, broń i inne).
- Dźwięki zdarzeń na stole i dwie melodie (menu i walka); wszystkie dźwięki są syntezowane, bez zewnętrznych plików.
- Lektor z głosem systemowym w języku interfejsu: nazwy legendarnych stworów i nowych bohaterów, emocje, kwestie bossów samouczka.
- Dziennik zmian: kliknięcie wersji w rogu menu otwiera całą historię zmian gry.
- Deck tracker w meczu: własna talia, pozostałe karty z szansą dobrania każdej jako następnej, karty zagrane przez przeciwnika. Każdy widok można ukryć; wybór jest zapamiętywany.
- Zegar tury w grze sieciowej: 75 sekund, w ostatnich 15 sekundach pali się lont; po upływie czasu tura kończy się sama.

### Zmieniono
- Historia tur oznacza początek tury na podstawie zdarzenia, a nie tekstu; panel historii nie przeskakuje w dół, gdy gracz czyta stare wpisy.
- Przyczyny desynchronizacji i domyślna nazwa gracza są tłumaczone.

### Naprawiono
- Przycisk „Poddaj się” nie zmieniał się w „Menu” po zakończeniu gry.

### Naprawiono (po przeglądzie)
- Historia tur po otwarciu pokazuje nowe tury.
- Zmiana języka w meczu zmienia też nagłówki deck trackera i historii, nazwę bota i otwarte okna.
- Długie teksty kart nie wychodzą poza ramkę.

## [0.5.0] - 2026-10-11

### Dodano
- Samouczek: sześć misji Jainą, jak w oryginale — Wyżer, Mełko Gromiłło, Wiedziciel Czo, Król Mukla, Hemet Nesingwary, Illidan Burzogniewny.
- Podpowiedzi krok po kroku, kwestie bossów, zasady pierwszych misji (nie można przegrać, nie można zakończyć tury z niewykorzystaną maną lub atakiem), moc bohatera odblokowuje się w piątej misji.
- Karty bossów samouczka: Wyżer MIAŻDŻYĆ!, Beczka, Stąpnięcie, Wola Mukli, Transcendencja, Płomienie Azzinotha, Wybuch płomieni i inne.
- Ekran nagrody po zwycięstwie; postęp samouczka jest zapisywany, ukończone misje można rozegrać ponownie.

## [0.4.0] - 2026-10-11

### Dodano
- Gra sieciowa w przeglądarce bez własnego serwera: WebRTC bezpośrednio między przeglądarkami, publiczny STUN Google. Gospodarz tworzy kod zaproszenia, gość odpowiada kodem odpowiedzi; kody można przekazać dowolnym komunikatorem.
- Synchronizacja meczu: obie strony sprawdzają stan gry po każdej turze; przy rozbieżności, złej wersji gry lub zerwaniu połączenia wyświetlany jest zrozumiały komunikat.
- Nazwa gracza (widoczna dla przeciwnika), 6 emocji i przycisk „wycisz przeciwnika”.

### Naprawiono (po przeglądzie)
- Mulligan w grze sieciowej wybierają obaj gracze jednocześnie.
- Pewniejsze łączenie przez różne sieci: gra czeka, aż przeglądarka znajdzie adres zewnętrzny; jest limit czasu połączenia z podpowiedzią.
- Zrozumiałe komunikaty: „przeciwnik wyszedł”, „inna wersja gry”, „różne dane kart”, „desynchronizacja”.
- Emocji nie można wysyłać częściej niż raz na 1,5 sekundy; „wycisz” od razu ukrywa pokazaną emocję.

## [0.3.0] - 2026-10-11

### Dodano
- Kolekcja: wszystkie 382 karty, strony po 8 kart, zakładki klas, filtr kosztu, wyszukiwanie, powiększona karta po najechaniu kursorem.
- Talie: nieograniczona liczba, tworzenie, edycja, kopiowanie, usuwanie; zasady Hearthstone (30 kart, 2 kopie, 1 legendarna, tylko własna klasa i neutralne).
- Talie są zapisywane w przeglądarce i zostają po ponownym uruchomieniu; uszkodzony plik nie przepada, tylko jest odkładany do `decks.bad.json`.
- Kody talii Hearthstone: eksport w formacie Classic; import kodów formatów Classic, Standard i Wild, w tym starych talii z lat 2014–2016 z oryginalnymi kartami oraz tekstu skopiowanego z klienta.
- Trening: wybór własnej talii; niepełnej talii nie można uruchomić.

### Naprawiono (po przeglądzie)
- Błąd importu kodu jest pokazywany w oknie importu.
- Talia z nieistniejącą już kartą otwiera się i można ją edytować; gracz dowiaduje się, że plik talii był uszkodzony (kopia jest zachowana).
- Importowane są kody talii z innymi wyglądami bohaterów (Magni, Medivh itd.) i kody z tekstu z nagłówkiem w pierwszej linii.
- Talia jest zapisywana po każdej zmianie, a nie tylko po naciśnięciu „Done”.

## [0.2.0] - 2026-10-11

### Dodano
- Menu główne, wybór klasy do treningu, podstawowe talie dziewięciu klas.
- Stół gry: bohaterowie, moce bohaterów, broń, sekrety, stoły, ręce, mana; mulligan, Wybierz jedno, wybór Tropienia, ekran końca gry.
- Sterowanie myszą: karta → wariant → miejsce na stole → cel; atak; moc bohatera; podpowiedź z powiększoną kartą.
- Proste efekty: wyskakujące liczby obrażeń i leczenia, cień zniszczonego stwora, drżenie ekranu przy silnych obrażeniach.
- Bot do treningu: sprawdza działania na kopii gry i wybiera najlepsze.
- Historia tur w trakcie meczu: wszystkie tury od początku, bez limitu długości; cudze dobrane karty są ukryte.
- Stół debugowania: scenariusz w JSON, wyszukiwanie karty i dodawanie jej na rękę, na stół lub do talii; gra z botem lub za obie strony; przycisk „Pozycja → JSON”.

### Naprawiono (po przeglądzie)
- Stwora można postawić między innymi, klikając sąsiedniego stwora.
- Historia nie pokazuje przeciwnikowi kart odrzuconych przez Tropienie.
- Stół debugowania zgłasza błędne typy pól scenariusza i nie uruchamia zepsutego meczu.
- Poddanie meczu wymaga potwierdzenia.
- Bot szybciej myśli w dużych pozycjach.

### Naprawiono
- Sekret jest traktowany jak zaklęcie: widzą go Żmij many, Arcymag Antonidas, Dziki piromanta, Licytator z Gadżetonu, Nauczycielka Purpurowych, Manoholiczka; Kontr-zaklęcie anuluje sekret.
- Szaleństwo cieni: skradziony stwór może atakować, nawet jeśli atakował w poprzedniej turze właściciela.
- Tropienie nie odrzuca kart, których gracz nie widział.
- Mulligan: wynik nie zależy od kolejności, w jakiej gracze potwierdzili wybór (ważne w grze sieciowej).
- Poddać się można w dowolnym momencie, także w turze przeciwnika i podczas mulligana.
- Scenariusze zachowują koszt kart na ręce, stan bohatera i licznik zagranych stworów; błąd w scenariuszu daje komunikat, a nie awarię.
- Świetlista istota nie zależy od kolejności aur; Ukrycie nie zdejmuje własnego Ukrycia stwora; Wężowa pułapka nie działa przy pełnym stole.
- Niepoprawne działanie (np. z sieci) jest odrzucane bez zmiany stanu.

## [0.1.0] - 2026-10-11

### Dodano
- Szkielet projektu Godot 4.7 i program uruchamiający testy.
- Dane 382 kart kolekcjonerskich formatu Classic (czerwiec 2014), tokenów i kart samouczka w 14 językach.
- Silnik: początek meczu, mulligan, Moneta, tura, mana, Przeciążenie, Wyczerpanie, palenie kart, odmrażanie.
- Silnik: pełna historia meczu (`history`) — każde działanie i wszystkie jego zdarzenia od początku meczu.
- Silnik: zagrywanie kart, Okrzyk bojowy, Kombinacja, Wybierz jedno, sekrety, broń, ataki, Prowokacja, Ukrycie, Szał wichru, moc bohatera, lista dozwolonych działań.
- Silnik: scenariusze — budowanie dowolnej pozycji z JSON i zapisywanie bieżącej pozycji do JSON (podstawa stołu debugowania).
- Karty: moce bohaterów wszystkich 9 klas, INFERNO!, Igła umysłu, Strzaskanie umysłu, Moneta.
- Karty: neutralne Basic (43).
- Karty: neutralne Classic COMMON (40).
- Karty: neutralne Classic RARE (36).
- Karty: neutralne Classic EPIC (11).
- Karty: neutralne legendarne, nagrodowe i promocyjne (27) oraz ich tokeny: Banany, karty Sen, Power Chord, wynalazki Gelbina, Uzdrawiający totem.
- Karty: Druid (25) i warianty Wybierz jedno.
- Karty: Hunter (25), sekrety łowcy, Tropienie.
- Karty: Mage (25), sekrety maga.
- Karty: Paladin (25), sekrety paladyna.
- Karty: Priest (25).
- Karty: Rogue (25), Kombinacja.
- Karty: Shaman (25), Przeciążenie.
- Karty: Warlock (25), Lord Jaraxxus.
- Karty: Warrior (25). Wszystkie 382 karty kolekcjonerskie formatu Classic są zaimplementowane.
- Kontrola kompletności: każda karta z efektem ma hak; 1000 losowych meczów bez błędów; silnik działa w wersji web, skrót zgodny z natywnym.
