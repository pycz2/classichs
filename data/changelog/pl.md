# Dziennik zmian

Format: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Wersjonowanie: [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.66.0] - 2026-11-10

### Dodano
- Panel administracyjny, strona gracza: dla każdej gry — ranga (ranga, gwiazdki, Legenda, seria, ukryte MMR; powrót do początku sezonu), ustawienia gry, talie (karty, kopiowanie kodu, dodanie z kodu sprawdzonego regułami, zmiana nazwy, usunięcie, kopiowanie innemu graczowi); przebieg Areny (wygrane, przegrane, reset, zakończenie); tag. Zmiany od razu docierają do gracza, jeśli jest online, i trafiają do dziennika. Kod talii (format Hearthstone) można skopiować wszędzie, gdzie panel pokazuje talie: w statystykach, na stronie meczu, u uczestników turnieju.

## [0.65.0] - 2026-11-10

### Dodano
- Bardzo trudny na serwerze: boty admina mogą grać na tym poziomie, a Legenda w rankingu, która długo czeka na przeciwnika, dostaje bota automatycznego Bardzo trudnego zamiast Trudnego (3 sekundy na decyzję na serwerze).

## [0.64.0] - 2026-11-10

### Zmieniono
- Bardzo trudny bot na treningu jest silniejszy: szuka planu na całą turę (przeszukiwanie wiązkowe), patrzy na odpowiedź przeciwnika i własną następną turę, a pozycje ocenia modelem wyuczonym na 2000 gier. Wygrywa 60% gier z Trudnym (400 gier na 19 taliach) i 72% ze Średnim. Jak dotąd myśli do 6 sekund na decyzję i kończy 10 sekund przed końcem swojej tury.

## [0.63.0] - 2026-11-10

### Dodano
- Panel administracyjny, statystyki: macierz klasa przeciw klasie (skuteczność wiersza przeciw kolumnie, liczba gier, od czerwieni do zieleni, lustra na przekątnej, suma każdej klasy); wybór wcześniejszych okresów — wczoraj, dowolny miniony dzień, tydzień, miesiąc, rok. Dzienne statystyki talii i kart są trzymane 400 dni; statystyki zajmują prawie o połowę mniej miejsca.

## [0.62.0] - 2026-11-10

### Dodano
- Panel administracyjny: wersja serwera w rogu każdej strony; pulpit pokazuje, ile miejsca zajmują baza danych i magazyn pakietów.
- Panel administracyjny: powtórka każdej gry wprost na jej stronie — Play otwiera ją na dole jak w kliencie (okrojona wersja webowa tylko z odtwarzaczem powtórek; pakiet gry pobiera z serwera). Zamyka się krzyżykiem albo przy zmianie strony.
- Panel administracyjny: statystyki w stylu HSReplay dla każdej gry — skuteczność klas według trybu i rangi, 20 najlepszych talii i 5 najlepszych każdej klasy, karty (w ilu taliach, kopie, skuteczność talii, jak często zagrywane i skuteczność po zagraniu, mulligan: zostawiona czy wymieniona), za tę godzinę, dzień, tydzień, miesiąc, rok i cały czas, z wykresami i angielskimi nazwami kart. Aktualizowane po każdej grze; wcześniejsze gry pochodzą z ich powtórek.

## [0.61.0] - 2026-11-10

### Dodano
- Boty serwera grają we wszystkie gry na serwerze, nie tylko w Klasykę: w każdą dołączoną lub wysłaną grę. Gdy w czasie ustawionym w panelu administracyjnym nie znajdzie się przeciwnik, przychodzi bot z talią z szablonów tej gry (albo talią startową klasy) i gra jej kartami.
- Na trening wraca bot Bardzo trudny — pierwszy trudny bot: waży każdą akcję w nawet 200 przypuszczeniach co do ukrytych kart i całą turę przeciwnika. Myśli, dopóki z jego tury zostało ponad 10 sekund, potem bierze najlepsze, co znalazł, i szybko kończy turę, więc nigdy się nie zawiesza i nie traci tury.

## [0.60.0] - 2026-11-10

### Dodano
- **Nowa gra, Naxxramas 2014**: wszystkie karty Podstawowe i Klasyczne oraz 30 kart Klątwy Naxxramas z ich żetonami, każda jak w dniu premiery przygody (22 lipca 2014): Grabarz +1/+1, Szlamobekacz 3/5, Reinkarnacja za 2, bez rasy Nieumarły, Łuk z Orlego Rogu rośnie tylko od twoich Sekretów (łatka 1.1.0.6024).
- Nowe mechaniki w silniku: podwójne Agonie (Baron Rivendare), Trucizna (Maexxna), stronnicy polegli w tej turze wracają (Kel'Thuzad), zaklęcia przeciwnika kosztują więcej (Loatheb), Feugen i Stalagg, Szalony Naukowiec, Zatrute Nasiona, Reinkarnacja i inne.
- 10 szablonów talii mety z 2014, boty, które grają w Naxxramas, własny wygląd (menu, stół, ekrany wyników) i uproszczone grafiki 2D dla nowych kart; instaluje się jak zwykły pakiet i jest na serwerze.

## [0.51.0] - 2026-11-10

### Zmieniono
- Karty Klasyczne i Podstawowe są jak w czerwcu 2014 (ostatnia łatka przed Naxxramas), według ówczesnych danych gry i historii w Hearthstone Wiki: Przywódca Defiasów 2/2; Zguba Zagłady zadaje 2 i przyzywa jednego z sześciu demonów z 2014; Łuk z Orlego Rogu rośnie od każdego ujawnionego Sekretu; Roześmiana Siostra kosztuje 3; wraca Sukkub (nie Spaczony Tropiciel); Cień Niczego znika na koniec tury; Mechy i Nieumarli z 2014 nie mają rasy; 37 tekstów i ponad 40 nazw jak w 2014 we wszystkich językach.
- Nozdormu działa: dopóki jest na stole, tura trwa 15 sekund — na serwerze, na treningu z botem i w grze przez kod (z lontem).

### Dodano
- Oryginalne głosy kart i bohaterów w twoim lokalnym pakiecie: dźwięk i kwestia stronnika, gdy wchodzi, atakuje i ginie, dźwięki zaklęć, emotki i kwestie bohaterów (za mało many, nie może atakować, początek gry). Pakiet buduje się lokalnie (tools/fetch_original_sounds.py, pack.py --sound-set i --voice) i nigdzie nie jest wysyłany.
- W twoim lokalnym pakiecie grafik: grafiki z 2014 kart, których grafika później się zmieniła (Sukkub, Harpia Wichrogniewu, Strażniczka Sekretów, Wypatroszenie, Ugryzienie, Śmiertelny Strzał, Rozłupanie Czaszki).

### Naprawiono
- Efekty w trakcie ataku dzieją się w połowie drogi: atak staje, Sekret się ujawnia i działa w pełni (Szlachetne Poświęcenie — atak trafia w Obrońcę, Zmylenie — w nowy cel, Lodowa Pułapka — atakujący wraca do ręki, Wyparowanie — atakujący ginie w locie, Wybuchowa Pułapka), a leczenie Czempionki z Prawdziwego Srebra też w połowie drogi.
- Boska Tarcza pęka w tej samej chwili, w której atakujący otrzymuje obrażenia.
- Wytrzymałość broni poniżej tej z karty jest czerwona, jak zranione zdrowie.
- Obrażenia od zaklęć na stronniku mają nowy magiczny efekt; śpiący stronnik wypuszcza zielone z; ukryte efekty (Zepsucie i inne) są oznaczone na stronniku i opisane na jego dużej karcie.
- Odrzucone karty wylatują w górę i płoną; karta skopiowana z ręki przeciwnika przylatuje z tej ręki.
- Pakiet gracza na serwerze może ważyć do 128 MiB (jak w kliencie).

## [0.50.0] - 2026-11-09

### Dodano
- **Turnieje** na serwerze: każdy tworzy turniej w menu gry „Turnieje”. Formaty: pucharowy (jedno lub dwa życia, z drabinką przegranych), system szwajcarski, każdy z każdym, drużynowy (Scheveningen). Serie Conquest lub Last Hero Standing, od Bo1 do Bo7, z banami lub bez. Zapisy, talie różnych klas, drabinka, miejsca z medalami dla pierwszej trójki, zakładki Nadchodzące, Zakończone, Zamknięte. Minuta na każdy krok meczu (przyjęcie gry, ban, wybór talii).
- **Powtórki**: każda gra na serwerze jest zapisywana; ostatnie 10 gier jest w menu gry „Powtórki”. Ogląda się je z przewijaniem po turach i akcjach, obie ręce odkryte. Eksport i import pliku powtórki.
- **Oglądanie** gry znajomego: „Oglądaj” na liście znajomych. W turniejach twórca i wyeliminowani gracze mogą oglądać mecze z odkrytymi rękami, jeśli twórca na to pozwala.
- **Rejestracja z kluczem zaproszenia**: admin włącza ją w panelu administracyjnym, tworzy klucze (notatka, liczba użyć) i widzi, kto przyszedł z jakim kluczem.
- W panelu administracyjnym: czas, po którym zamiast żywego przeciwnika przychodzi bot (od 0 do 10 minut), strony kluczy zaproszeń i turniejów, pobieranie powtórki gry.
- Paralaksa w menu głównym: obraz, cząsteczki i pył przesuwają się za myszą lub przechyleniem telefonu.

## [0.42.2] - 2026-11-05

### Zmieniono
- Ekran dotykowy: z małej ręki nie da się już od razu wyciągnąć karty. Pierwsze dotknięcie tylko otwiera rękę (jak w 0.42.0).

## [0.42.1] - 2026-11-05

### Naprawiono
- Szukanie gry na serwerze z talią zapisaną na serwerze nigdy się nie kończyło: serwer odrzucał talię z powodu pola z notatkami. Teraz klient go nie wysyła, serwer przyjmuje takie talie, a odmowa kończy szukanie.
- Gry na serwerze (Arena, rankingowe, zwykłe) zawieszały się, gdy stronnik wchodził na stół: numery z odpowiedzi serwera nie zgadzały się z numerami na stole.
- Pełna talia nie zasłania już zegara gry: stos rośnie w dół.
- Stronnik puszczony na stół podczas animacji od razu staje na swoim miejscu i tam czeka, zamiast wracać do ręki.
- Ekran dotykowy: kartę można od razu wyciągnąć z małej ręki, bez osobnego dotknięcia, by ją otworzyć.

## [0.42.0] - 2026-11-03

### Dodano
- Ekran dotykowy (Android i przeglądarki): ręka czeka mała w prawym dolnym rogu; dotknięcie ją otwiera, dotknięcie obok zamyka.
- Ekran dotykowy: dotknięcie karty w ręce tylko ją pokazuje. Karta zostaje zagrana tylko, gdy przeciągniesz ją ponad dolną jedną trzecią ekranu; puszczona niżej wraca do ręki.
- Ekran dotykowy: wszystkie listy (talie, kolekcja, gry, serwer, znajomi, czat, historia i inne) przewijają się palcem, także gdy ruch zaczyna się na przycisku; szybkie przesunięcie przewija dalej siłą rozpędu.
- Ekran dotykowy: długie przytrzymanie pokazuje podpowiedź (karty w talii, twojej i przeciwnika; dlaczego talii nie można zagrać; co robią przyciski) i działa jak prawy przycisk (emotki twojego bohatera).
- Ekran dotykowy: w kolekcji i w drafcie Areny dotknięcie dodaje kartę; długie przytrzymanie tylko ją pokazuje.

### Zmieniono
- Talia na stole jest wyraźnie grubsza, gdy ma dużo kart, i cieńsza, gdy ma mało.

### Naprawiono
- Stronnik, którego kładziesz, stoi w wybranym miejscu, gdy działa jego Okrzyk bojowy, i potem się nie rusza (wcześniej na chwilę wracał do ręki i przylatywał z powrotem).

## [0.41.1] - 2026-11-03

### Naprawiono
- „Wyślij grę” na serwer proponuje teraz także twoją własną wersję gry, którą serwer już ma (te same zasady, własne obrazki): na przykład Classic z twoim zestawem grafik.

## [0.41.0] - 2026-11-03

### Dodano
- Samouczek do Neonfall: sześć misji z bossami, od pierwszej karty do wszystkich mechanik gry, w ośmiu językach.
- Dodawanie gry z pliku pokazuje, co się dzieje: czytanie pliku z paskiem postępu, potem sprawdzanie.

### Naprawiono
- W paczce Classic nie było widać rosyjskich liter: jej czcionka tytułów nie ma cyrylicy. Brakujące litery biorą się teraz z czcionki klienta, a tytuł w menu gry jest pisany wielkimi literami.
- Stronnik z Okrzykiem bojowym najpierw ląduje na stole (pozostali robią mu miejsce), potem działa Okrzyk, potem stronnik się ustawia.
- Karta dobrana przez inną kartę (Początkujący inżynier) przylatuje z talii, a nie od stronnika.
- Własny zestaw grafik zaimportowanej paczki (zbudowany z folderu twórcy) można teraz wybrać.

## [0.40.0] - 2026-11-03

### Zmieniono
- Gra nazywa się **Classic Heroes Showdown** (w skrócie Classic HS). To teraz silnik gier karcianych: każda gra to paczka z własnymi zasadami, kartami, wyglądem, muzyką, samouczkiem i szablonami talii.
- Nowe menu: Graj, Ustawienia, Wyjście. Graj → Bezpośrednio (biblioteka gier, potem menu wybranej gry w jej stylu) lub Serwer (połączenia, logowanie, strona serwera ze znajomymi i grami serwera).
- Ustawienia ogólne: język, głośność, rewers kart, szybkość animacji, drżenie ekranu, pełny ekran. Zestawy grafik i muzyki wybiera się dla każdej gry (w trybie serwera zapisywane na serwerze); narzędzia debugowania są w ustawieniach wewnątrz gry.
- Talie są przypisane do gry; na serwerze to talie serwera dla tej gry, a lokalne można tam skopiować. Na liście nie ma już gotowych talii: nowa talia zaczyna się od zera albo od szablonu z paczki.
- Samouczek i efekty sceny (deszcz, śnieg, iskry) są teraz częścią paczki. Wygląd karczmy przeniósł się do paczki Classic; sam klient wygląda neutralnie.

### Dodano
- Narzędzia paczek w bibliotece gier: zbudować grę z folderu, sprawdzić ją (pliki, JSON, skrypty Lua z numerem wiersza, grafiki, tłumaczenia, samouczek), rozegrać próbne partie botów, zainstalować.
- Strona ma dział „Dla twórców”: własna gra, skrypty kart w Lua, opis API silnika, sprawdzanie i testy, interaktywna mapa architektury. Strona główna jest w stylu Neonfall.
- Przy aktualizacji ustawienia przenoszą się same: zestawy grafik i muzyki do Classic, serwery do połączeń, twoje talie do ich gry.

## [0.32.0] - 2026-11-02

### Dodano
- Talie można trzymać na serwerze gry: znak chmury przy talii. Talia zapisuje się przy każdej zmianie i pojawia się na innych urządzeniach po zalogowaniu.
- Nowy zestaw obrazów „Prosty 2D” dla Neonfall.
- Telefony: długie przytrzymanie pola tekstowego otwiera menu (Wklej, Zaznacz wszystko, Kopiuj, Wytnij); przy haśle logowania jest przycisk Wklej.

### Naprawiono
- Ruchy są widoczne po kolei i krok po kroku: karta przeciwnika wylatuje z ręki, strzałka pokazuje cel, a każdy efekt widać osobno (Tajemne pociski i Szalony bombowiec trafiają po jednym). Działa to w obie strony i przy szybkiej animacji.
- Mulligan: wymienione karty wracają do talii, nowe stają na ich miejscach, potem pojawia się Moneta, a karty trafiają do ręki w tej samej kolejności.
- Android: nie dało się wkleić skopiowanego hasła w pole logowania.
- Podczas szukania gry na serwerze działa tylko Anuluj: inne tryby, arena, wylogowanie i zmiana gry czekają, aż wyszukiwanie zostanie anulowane.
- Wersja przeglądarkowa nie ładuje już starej wersji z pamięci podręcznej: nowa wersja wczytuje się przy zwykłym odświeżeniu.

## [0.31.0] - 2026-10-30

### Dodano
- Trening z mądrym botem na wybranym poziomie: łatwy, średni lub trudny. To ten sam bot co na serwerze; widzi tylko swoje karty. Działa na wszystkich platformach i bez internetu; bot myśli w tle, a gra się nie zacina.
- Serwer: gracz, który czeka sam 30 sekund w kolejce rankingowej, zwykłej lub areny, dostaje autobota na jedną grę. Jego siła zależy od ukrytego rankingu gracza, na arenie — od zwycięstw w serii.
- Boty na arenie biorą losowego bohatera z trzech; łatwy bot wybiera karty losowo, średni zwykle najlepsze, trudny zawsze najlepsze pod krzywą many.
- Po najechaniu na kartę widać karty, które tworzy lub przywołuje (żetony, przemiany, karty Wybierz jedno, moc bohatera).
- Edytor talii pokazuje krzywą many nad listą kart.

### Naprawiono
- Boty serwera nie zawieszają się już na minuty przy pełnym stole i nie przegrywają przez spóźnione ruchy. Ruch, który przyjdzie po końcu tury, serwer odrzuca bez kary — to chroni też graczy z wolnym łączem.
- Silnik zasad jest szybszy: kopia partii około 10 razy, ruch 3,5 razy.

## [0.30.0] - 2026-10-26

### Dodano
- Gra przez kody (bezpośrednio, bez serwera) działa teraz nie tylko w przeglądarce, ale też na Windows, macOS, Linux i Android. Także między różnymi platformami, na przykład przeglądarka przeciw Androidowi.

### Naprawiono
- Firefox: Ctrl+V i Cmd+V nie wklejały tekstu do pól, a kliknięcie pola otwierało menu „Wklej”. Wklejanie działa, a menu już się nie pojawia.

## [0.29.2] - 2026-10-25

### Naprawiono
- Android: aplikacja nie mogła połączyć się z serwerem gry — logowanie, rejestracja, gra online, pobieranie gier. W kompilacji brakowało uprawnienia do internetu; teraz jest, a kompilacja to sprawdza.

## [0.29.1] - 2026-10-24

### Dodano
- Panel serwera: własna ikona karty — złoty kafelek z ciemnym rombem z logo.

## [0.29.0] - 2026-10-24

### Dodano
- Boty na serwerze: serwer uruchamia własnych graczy Classic — w grach rankingowych, zwykłych i na Arenie — żeby zawsze było z kim zagrać. Panel administracyjny serwera ma nową stronę „Bots”: liczba, siła (łatwe, średnie, silne), tryby, harmonogram i przerwy; włączanie i wyłączanie na żywo; co robi każdy z nich, jego gra jego oczami, ostatnia decyzja i dziennik.
- Boty grają uczciwie: jak każdy gracz, tym samym protokołem, i widzą tylko swoją stronę; ukryte karty przeciwnika oceniają według prawdopodobieństwa.

## [0.28.4] - 2026-10-24

### Dodano
- Nowy zestaw obrazów dla Classic, „Fotorealistyczny”: wszystkie 534 karty w stylu fotorealistycznym z bardzo małą liczbą szczegółów. Wybór: Gry → Classic 2014 → Obrazy kart (albo w ustawieniach).

### Naprawiono
- Android: gra nie zawiesza się już na ekranie startowym. Kompilacja kompresowała wbudowane gry (paczki) w APK i Android czytał je minutami; teraz są zapisane bez kompresji, a gra otwiera się w kilka sekund.
- Przeglądarka: Ctrl+V (Cmd+V) w polu tekstowym wkleja to, co jest teraz w schowku. Wcześniej pierwsze wklejenie dawało poprzednią zawartość (albo nic), np. hasło skopiowane z menedżera haseł.
- Android: pole hasła jest oznaczone jako hasło, więc klawiatura i menedżer haseł mogą podsunąć zapisane hasło; adres serwera ma klawiaturę do adresów.
- Telefony: pole tekstowe unosi się nad klawiaturę ekranową; wcześniej klawiatura zasłaniała pola na dole ekranu i nie było widać wpisywanego tekstu. Podpowiedź na liście serwerów nie wchodzi już pod przycisk „Zamknij”.

## [0.28.3] - 2026-10-24

### Naprawiono
- Android: biblioteka zasad gry jest zbudowana dla stron pamięci 16 KB (telefony z Androidem 15 i nowszym). Takie telefony uruchamiały grę w trybie zgodności albo wcale.
- Nie ma już domyślnego serwera: gra uruchamia się i działa bez serwera; serwer dodasz później w Ustawienia → Serwery gry (albo przyciskiem serwera w Grze sieciowej).

## [0.28.2] - 2026-10-23

### Dodano
- Nowy zestaw obrazów dla Classic, „Prosty malowany”: wszystkie 534 karty jako malowane ilustracje z bardzo małą liczbą szczegółów. Wybór: Gry → Classic 2014 → Obrazy kart (albo w ustawieniach).

## [0.28.1] - 2026-10-19

### Dodano
- Nowy zestaw obrazów dla Classic, „Kreskówka 2D”: wszystkie 534 karty w płaskim stylu kreskówki. Wybór: Gry → Classic 2014 → Obrazy kart (albo w ustawieniach).

## [0.28.0] - 2026-10-16

### Dodano
- Nowa gra Neonfall: cyberpunk w zatopionym Vesper Arc. Trzech czempionów (Iris Null, Mother Rust, Director Vale), 60 nowych kart, własne grafiki, dźwięki, muzyka, czcionki i neonowy wygląd. To domyślna gra serwera.
- Ekran „Gry”: wybór gry, zestawów grafik, dźwięków i muzyki, dodanie własnej gry z pliku .cardpack (także w przeglądarce), usuwanie pobranych.
- W grze bezpośredniej kodami znajomy może przesłać brakującą grę: zgoda, przesyłanie z postępem, sprawdzenie integralności.
- Kilka serwerów gry w ustawieniach, każdy z własnym logowaniem i znajomymi. Zalogowanie na to samo konto gdzie indziej zamyka poprzednią sesję („Zalogowano na innym urządzeniu”).
- Serwer udostępnia gry: kolejki, rangi i Arena osobno dla każdej gry; gra towarzyska na własnej grze znajomego, pobranej za zgodą.
- Sprawdzanie podpisu Androida: python3 tools/android_keystore_check.py otwiera stronę, która sprawdza sekrety GitHuba i tworzy nowy klucz.

### Zmieniono
- Silnik nic już nie wie o Hearthstone: cała gra — zasady, karty, ich logika w małym Lua, teksty, grafiki, dźwięki, rangi, zegary — mieści się w pliku .cardpack. Classic 2014 stał się takim pakietem i został sprawdzony na 7833 nagranych partiach: wyniki zgadzają się co do bitu.
- Protokół gry bezpośredniej to wersja 3: starsze wersje nie mogą grać z tą.

## [0.27.1] - 2026-10-15

### Naprawiono
- Wersje na Windows i Linuksa znów się uruchamiają: moduł zasad jest teraz dostarczany obok gry. Windows to .zip (ClassicHS.exe z plikiem .dll obok); AppImage ma go w środku. Obrazy dokumentacji nie trafiają już do gry.

## [0.27.0] - 2026-10-15

### Dodano
- Serwer gry: nowe lobby w stylu gry — pudełka talii z bohaterami, przełącznik Zwykła/Rankingowa, medal rangi z gwiazdkami, duży przycisk Graj; Arena z biletem, dużymi portretami bohaterów, draftem i ekranem przebiegu do 12 zwycięstw.
- Logowanie do serwera jest zapamiętywane: gra loguje się sama przy starcie. Gdy jesteś zalogowany, na każdym ekranie jest przycisk znajomych: kto jest online, szuka gry lub gra, zaproszenia do znajomych, okna czatu nad grą i zaproszenia do gry, które przyjmiesz z dowolnego miejsca.
- Nowy panel administratora serwera: dashboard na żywo, dziennik zdarzeń z filtrami (logowania, wiadomości, ruchy, błędy), partie z ruchami w czasie rzeczywistym, konta, rozmowy; motywy ciemny i jasny.

### Zmieniono
- Wszystkie zasady gry są teraz w jednym module w Rust: działa w grze na każdej platformie (w przeglądarce jako WebAssembly) i na serwerze; okno gry tylko rysuje. Zasady sprawdzono na 7833 nagranych partiach: wyniki zgadzają się ze starym silnikiem co do bitu.
- Gry przez serwer: serwer prowadzi partię i wysyła każdemu tylko to, co może widzieć — ukryte karty przeciwnika nigdy nie trafiają na twój komputer. Zegar tury działa na serwerze; po zerwaniu połączenia możesz wrócić do partii.
- Gra bezpośrednia kodami: obie gry sprawdzają każdy ruch; jeśli się różnią, partia kończy się dla obu z komunikatem „coś się nie zgadza” (nikt nie dostaje bana). Starsze wersje nie mogą grać z tą.

## [0.26.1] - 2026-10-15

### Naprawiono
- W pobranej grze na Windows, macOS, Linuxa i Androida „Gra sieciowa” teraz działa: można grać przez serwer gry. Gra bezpośrednia kodami nadal działa tylko w wersji przeglądarkowej.

## [0.26.0] - 2026-10-15

### Dodano
- Serwer gry (eksperymentalny, opcjonalny): Gra sieciowa → „Przez serwer gry”. Konto z hasłem, zwykłe i rankingowe gry (25 rang z 2014 roku i Legenda, gwiazdki, co miesiąc nowy sezon; ukryty ranking szuka równego przeciwnika), Arena do 12 zwycięstw lub 3 porażek, znajomi po tagu, wiadomości, zaproszenia do gry towarzyskiej i blokowanie. Serwer sprawdza każdy ruch regułami samej gry. Adres serwera jest w Ustawienia → „Serwer gry” (domyślnie ws://localhost:7377). Sam serwer (Rust, folder server/) nie jest nigdzie hostowany: uruchamiasz go sam; każde wydanie zawiera serwer dla Windows, macOS i Linuxa. Gra bezpośrednia kodami zostaje bez zmian.

## [0.25.1] - 2026-10-15

### Naprawiono
- Sekrety przeciwnika są na górze jego portretu, jak twoje (wcześniej pod nim).

## [0.25.0] - 2026-10-15

### Dodano
- Wersje na wszystkie platformy: każda wersja dostaje wydanie na GitHubie z grą na Windows (.exe), Linux (.AppImage), macOS (.zip), Android (.apk) i wersją webową (.zip). Strona ma link: „Pobierz grę”.

## [0.24.1] - 2026-10-12

### Zmieniono
- Talie podstawowe zniknęły z list talii: każda klasa ma talię klasyczną. Talia podstawowa pojawia się tylko dla klasy bez talii klasycznej (obecnie żadnej). Niezmienione talie podstawowe znikają raz z zapisanych talii; zmienione zostają.

## [0.24.0] - 2026-10-12

### Dodano
- Ustawienia → Zestaw muzyki: generowana albo otwarta (CC0) — średniowieczna muzyka z karczmy od RandomMind: „Minstrel Dance” w menu, „The Old Tower Inn”, „King's Feast” i „The Bard's Tale” w grze. Dźwięki zostają generowane.

## [0.23.3] - 2026-10-12

### Zmieniono
- Mulligan jak w oryginale: wybrane karty lecą do talii, nowe zajmują ich miejsca i zostają przed tobą („Czekamy na przeciwnika…”); gdy przeciwnik wybrał, drugiemu graczowi obok pojawia się Moneta, potem wszystkie karty schodzą do ręki w tej samej kolejności i dopiero wtedy dobierana jest karta pierwszej tury. Ręka pod ekranem mulligana jest ukryta.
- Przycisk śledzenia talii jest pod przyciskiem menu i nie zasłania już kryształów many przeciwnika.

## [0.23.2] - 2026-10-12

### Zmieniono
- Karta z Kombinacją w ręce, którą można zagrać, świeci na żółto zamiast na zielono, gdy w tej turze zagrano już kartę (Kombinacja zadziała).
- Moneta zawsze pojawia się z własną animacją — obraca się w złotym świetle i trafia do ręki — także gdy przeciwnik skończył mulligan później, i u obu graczy.

## [0.23.1] - 2026-10-12

### Naprawiono
- Przycisk wyciszania przeciwnika pokazuje stan: „Wycisz”, a gdy przeciwnik jest wyciszony — „Wyłącz wyciszenie”.

## [0.23.0] - 2026-10-12

### Zmieniono
- Mulligan: po „Potwierdź” nowe karty od razu trafiają do ręki, bez czekania na przeciwnika, i zajmują miejsca wymienionych — ręka zachowuje kolejność z ekranu mulligana; potem „Czekamy na przeciwnika…”. W sieci wszystko zostaje zgodne: tasowanie przy mulliganie używa własnego strumienia losowego każdego gracza.
- Licznik mulligana w sieci nie ma lontu: przez ostatnie 10 sekund pod „Potwierdź” świecą czerwone cyfry.
- To, na co wskazuje przeciwnik, nie gasi już twojej poświaty: zielona lub żółta zostaje, z lekkim czerwonym pierścieniem na zewnątrz.
- Karta spalona przez pełną rękę płonie tylko shaderem, bez unoszących się trójkątów.

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
