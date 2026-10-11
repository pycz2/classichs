# Registro de cambios

Formato: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Versiones: [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.13.0] - 2026-10-11

### Añadido
- Mulligan: las cartas cambiadas vuelan al mazo, las nuevas ocupan su lugar, la moneda aparece girando con luz dorada y luego toda la mano baja. Las cartas marcadas para cambiar llevan un sello rojo con una cruz blanca.
- Fatiga: una carta oscura con una calavera y su daño vuela del mazo vacío al héroe.
- Una carta quemada (mano llena) se muestra y arde en llamas.
- Al pasar sobre un mazo también se ve cuántas cartas tiene ese jugador en la mano.

### Cambiado
- El maná que gastaría la carta bajo el ratón pulsa claramente, si hay suficiente.
- El brillo de cartas y botones jugables es más estrecho y más intenso en el borde.

## [0.12.2] - 2026-10-11

### Cambiado
- Las cartas jugables, los esbirros, el poder de héroe y el botón «Fin de turno» tienen un brillo suave y pulsante en lugar de un contorno.

## [0.12.1] - 2026-10-11

### Añadido
- Al pasar el ratón sobre una carta de la mano parpadean los cristales de maná que gastaría, si se puede jugar.

## [0.12.0] - 2026-10-11

### Añadido
- Efectos en la mesa: hechizos, gritos de batalla, últimos alientos y efectos de inicio y fin de turno lanzan proyectiles desde su origen a cada objetivo. Al impactar, cada esbirro y héroe muestra lo que le pasa: una explosión por daño, chispas por sanación, flechas por mejora o penalización, un destello por una palabra clave nueva, hielo, un anillo de silencio, humo de transformación, un portal de invocación, una calavera de último aliento, un destello de grito de batalla, un remolino al cambiar de control, un escudo de armadura.
- Los números que cambian en las cartas crecen un momento con su gema.
- La raza de la carta (Bestia, Demonio, Dragón, Múrloc, Robot, Tótem, Pirata, No-muerto) en una placa abajo de la carta.
- Un esbirro inmune brilla en blanco con chispas girando a su alrededor.

### Cambiado
- El escudo de Provocar sigue el contorno del retrato.
- «Tu turno» aparece después de los efectos de fin de turno.

## [0.11.0] - 2026-10-11

### Añadido
- Seis reversos de carta para elegir en los ajustes: Clásico, Horda, Druida, Arcano, Oro, Noche.
- Laboratorio de efectos en la mesa de depuración: cualquier carta en la mesa y en la mano con sus ventanitas; palabras clave, mejoras, penalizaciones, auras, daño, silencio, sueño, cambios de coste y brillos se activan y desactivan en cualquiera de los 8 idiomas.

### Cambiado
- La mesa cambia en el momento del golpe: los números, los escudos y las muertes se ven cuando el atacante toca su objetivo o llega el proyectil del hechizo, no antes. Un esbirro que muere se desvanece con sus últimos números.

### Corregido
- En la versión web había un rectángulo blanco en lugar del dragón sobre el título del menú.
- Las cartas de la página del juego las dibuja el propio juego y se ven como en el juego.

## [0.10.0] - 2026-10-11

### Añadido
- Cada carta tiene ahora su propia imagen generada.
- El texto de las cartas está maquetado a mano para cada carta en cada idioma: las líneas, el tamaño de letra y la posición. Una comprobación asegura que ningún texto se sale del marco ni pisa las gemas; las líneas son equilibradas, los números van con su palabra y las palabras clave no se cortan.
- Laboratorio de cartas (en la mesa de depuración): una carta en los 8 idiomas a la vez con sus marcos y una lista de problemas; los tamaños, la posición y las líneas se pueden cambiar y guardar.
- Los esbirros muestran sus cambios en ventanitas: mejoras con la carta que las dio, auras, valores fijados, palabras clave obtenidas, Congelado, Silenciado. Ventanitas de palabras clave también en la colección y al crear mazos.
- Cartas legendarias: un friso dorado y recto con un dragón a lo largo del borde superior de la carta.
- La pantalla de carga con el aspecto actual del menú.

### Cambiado
- La espada detrás de la gema de ataque sobresale arriba a la izquierda, fuera del borde de la carta, lejos del texto.
- Más contraste en los números de las cartas, sobre todo en valores mejorados y dañados.

### Corregido
- El texto francés de algunas cartas mostraba «|4(point,points)» en lugar de «point» o «points».
- En la página del juego, la última letra del título ya no se corta.

## [0.9.0] - 2026-10-12

### Añadido
- Menú principal: un fondo de taberna generado con un zoom lento, chispas voladoras, un título dorado vectorial con un dragón y un destello que recorre el texto; los botones aparecen uno tras otro.
- Fondos generados: la partida se juega sobre un tablero de piedra en una mesa de taberna, la elección de mazo y la colección están en una biblioteca de taberna, y el resto de pantallas, en una taberna oscurecida.
- Fuente Alegreya para la interfaz (latino, cirílico, griego) y botones de madera al estilo de la taberna, con esquinas redondeadas y marco dorado; campos de entrada redondeados, deslizadores dorados.
- Los textos de las cartas siempre caben en el marco: el tamaño de la fuente se ajusta midiendo para cada carta y cada idioma. Palabras clave en negrita.
- Cuadros con la explicación de las palabras clave junto a la carta ampliada.
- Una espada detrás de la piedra de ataque, un pequeño dragón generado en las cartas legendarias.
- El poder de héroe se da la vuelta tras usarse; el botón «Finalizar turno» brilla en verde cuando no quedan jugadas.
- Filtro de rareza en la colección y al crear mazos.
- Listas de mazos como en el original: una franja con el retrato del héroe tras el nombre del mazo, una franja con la ilustración de la carta en la lista de cartas del mazo, el coste en un cristal, el llenado del mazo como una barra.
- El registro de cambios se abre en el idioma del juego.
- El juego se puede instalar como aplicación (PWA) y jugar sin conexión tras la primera carga.
- En la página del juego, las capturas de pantalla están en inglés.

### Corregido
- Las intenciones repetidas o demasiado frecuentes del rival ya no sobrecargan la mesa; la carta emergente del historial no se vuelve a crear con cada movimiento del ratón; la confirmación del mulligan cede ante el temporizador y la pérdida de conexión; una carta arrastrada permanece sobre la mesa.

## [0.8.1] - 2026-10-11

### Corregido (tras la revisión)
- En las partidas en línea, el temporizador podía terminar por sí solo un turno nuevo mientras aún se reproducía la animación del turno del rival.
- El clic derecho durante el arrastre de una carta lo cancela sin errores.
- Las cartas de la mano ya no se dibujan por encima de los ajustes, el menú, el mulligan y la pantalla de fin de partida.
- Un esbirro devuelto a la mano o transformado cambia en su sitio, en lugar de «morir» y aparecer con una carta nueva del mazo.

## [0.8.0] - 2026-10-11

### Añadido
- Mesa como en el original: esbirros ovalados con piedra de ataque y gota de salud, escudo de piedra de provocar, dragón dorado sobre los legendarios, marcos de cartas con cinta de nombre y pergamino, retratos de héroe en arco con el emblema de la clase.
- Efectos animados en la mesa: Viento furioso, escudo divino, embozo, congelación, sueño, activadores, último aliento, auras, enardecimiento, daño de hechizos, silencio.
- Arrastrar cartas: la carta sigue al cursor, los esbirros se apartan para dejar sitio donde se insertará, flechas curvas para hechizos, ataques y poder de héroe. Seleccionar con clics también funciona.
- Animaciones: robar una carta del mazo, jugar una carta (la carta del rival se da la vuelta a mitad de camino), vuelo de hechizos, ataque de esbirros y del héroe, poder de héroe, muerte, vuelta a la mano, mulligan, revelación de un secreto, cartel «Tu turno», frases con el héroe «hablando». El bot espera a que terminen las animaciones.
- Mano en abanico: la carta bajo el cursor se levanta y se agranda.
- Mazo junto al héroe: el grosor depende del número de cartas, el número exacto aparece al pasar el cursor.
- Menú de engranaje en la esquina superior derecha: historial, rastreador de mazo, ajustes, rendirse. Emotes con clic derecho sobre tu héroe, «Silenciar» sobre el héroe del rival.
- Barra de historial a la izquierda: imágenes de las cartas jugadas, la carta al pasar el cursor, el historial de texto al hacer clic.
- En las partidas en línea se ve adónde mira el rival: la carta levantada en su mano, su flecha roja, el esbirro resaltado.
- Imágenes de cartas: ilustraciones generadas (Codex local), arte original (solo para el juego local) y conjuntos propios: cualquier carpeta en `art/`; se elige en los ajustes. Donde no hay imagen, arte dibujado, distinto para cada carta.
- Ajuste de velocidad de las animaciones: de normal a 4 veces más rápido.
- Mazo básico para cada héroe en el primer inicio.
- Iconos de clase en la colección, en la elección de héroe y de rival; los filtros de coste son cristales de maná.
- Página del juego en 8 idiomas, con imágenes de cartas, retratos de héroes, abanico de cartas, chispas y contadores.

### Cambiado
- Música nueva al estilo de una taberna: laúd y arpa pulsados, flauta, pad, bajo, pandero y shaker, eco y reverberación. El menú es un vals tranquilo, en combate hay tres temas distintos de 60 a 90 segundos. Cada partida empieza con un tema distinto del anterior y, al acabar el tema, suena el siguiente.
- Cristales de maná en lugar del texto «Maná 3/5».

## [0.7.0] - 2026-10-11

### Añadido
- Página del juego en GitHub Pages: https://pycz2.github.io/classichs/ — cabecera animada, características, galería de capturas de pantalla, ruso e inglés; el juego se puede iniciar directamente en la página.
- `README.md` con capturas de pantalla, características, compilación y estructura del proyecto.
- `tools/build_site.sh`: compilación del sitio y publicación en la rama `gh-pages`.

### Cambiado
- El ejemplo en la mesa de depuración es una posición de escaparate: secreto, arma, provocar, esbirros legendarios, mano llena.
- Las frases en ruso del jefe de la primera misión usan el nombre oficial «Hogger».

### Corregido
- Los símbolos que no estaban en la fuente se mostraban como cuadrados: los iconos de esbirros (último aliento, activador, silencio) ahora son vectoriales y la flecha es ASCII. Una prueba comprueba que la fuente contiene todos los símbolos de la interfaz y de las traducciones.

## [0.6.0] - 2026-10-11

### Añadido
- Interfaz en 8 idiomas: English, Русский, Deutsch, Français, Español, Português (Brasil), Italiano, Polski. El idioma por defecto es el del sistema; el cambio de idioma en los ajustes es inmediato, sin reiniciar.
- Pantalla de ajustes (desde el menú y desde la partida): idioma, volumen de música, sonidos y voz, locución, sacudida de pantalla, pantalla completa, nombre del jugador.
- Arte vectorial para cada carta, héroe y poder de héroe: motivo según el nombre, la raza, el tipo y la clase (fuego, hielo, yeti, oveja, múrloc, arma y otros).
- Sonidos de los eventos de la mesa y dos melodías (menú y combate); todos los sonidos son sintetizados, sin archivos externos.
- Locución con la voz del sistema en el idioma de la interfaz: nombres de esbirros legendarios y de héroes nuevos, emotes, frases de los jefes del tutorial.
- Registro de cambios: al hacer clic en la versión en la esquina del menú se abre todo el historial de cambios del juego.
- Rastreador de mazo en la partida: tu mazo, las cartas restantes con la probabilidad de robar cada una a continuación, las cartas que ha jugado el rival. Cada vista se puede ocultar; la elección se recuerda.
- Temporizador de turno en las partidas en línea: 75 segundos, en los últimos 15 segundos arde la mecha; al agotarse el tiempo, el turno termina solo.

### Cambiado
- El historial de turnos marca el inicio del turno por evento y no por texto; el panel del historial no salta hacia abajo mientras el jugador lee entradas antiguas.
- Los motivos de desincronización y el nombre de jugador por defecto se traducen.

### Corregido
- El botón «Rendirse» no se convertía en «Menú» tras el fin de la partida.

### Corregido (tras la revisión)
- El historial de turnos muestra los turnos nuevos tras abrirse.
- El cambio de idioma en la partida cambia también los títulos del rastreador de mazo y del historial, el nombre del bot y las ventanas abiertas.
- Los textos largos de las cartas ya no se salen del marco.

## [0.5.0] - 2026-10-11

### Añadido
- Tutorial: seis misiones con Jaina Valiente, como en el original — Hogger, Molino Tormenta de Maná, Eremita Cho, Rey Mukla, Hemet Nesingwary, Illidan Tempestira.
- Pistas paso a paso, frases de los jefes, reglas de las primeras misiones (no se puede perder, no se puede terminar el turno con maná o ataque sin gastar), el poder de héroe se desbloquea en la quinta misión.
- Cartas de los jefes del tutorial: ¡Hogger MACHACA!, Barril, Pisotón, Voluntad de Mukla, Transcendencia, Llamas de Azzinoth, Ráfaga de llamas y otras.
- Pantalla de recompensa tras la victoria; el progreso del tutorial se guarda y las misiones superadas se pueden rejugar.

## [0.4.0] - 2026-10-11

### Añadido
- Partida en línea en el navegador sin servidor propio: WebRTC directamente entre navegadores, STUN público de Google. El anfitrión crea un código de invitación, el invitado responde con un código de respuesta; los códigos se envían por cualquier mensajero.
- Sincronización de la partida: ambas partes comprueban el estado del juego tras cada turno; si hay discrepancia, versión del juego incorrecta o corte de la conexión, se muestra un mensaje claro.
- Nombre del jugador (lo ve el rival), 6 emotes y el botón «silenciar al rival».

### Corregido (tras la revisión)
- En las partidas en línea, ambos jugadores eligen el mulligan a la vez.
- Conexión más fiable entre redes distintas: el juego espera a que el navegador encuentre la dirección externa; hay un tiempo de espera de conexión con una pista.
- Mensajes claros: «el rival se ha ido», «otra versión del juego», «datos de cartas distintos», «desincronización».
- Los emotes no se pueden enviar más de una vez cada 1,5 segundos; «silenciar» oculta al instante el emote mostrado.

## [0.3.0] - 2026-10-11

### Añadido
- Colección: las 382 cartas, páginas de 8 cartas, pestañas de clases, filtro por coste, búsqueda, carta ampliada al pasar el cursor.
- Mazos: cantidad ilimitada, creación, edición, copia, eliminación; reglas de Hearthstone (30 cartas, 2 copias, 1 legendaria, solo de tu clase y neutrales).
- Los mazos se guardan en el navegador y permanecen tras reiniciar; un archivo dañado no se pierde, sino que se aparta en `decks.bad.json`.
- Códigos de mazo de Hearthstone: exportación en formato Classic; importación de códigos de formatos Classic, Standard y Wild, incluidos mazos antiguos de 2014–2016 con cartas originales y texto copiado del cliente.
- Entrenamiento: elección de tu mazo; un mazo incompleto no se puede iniciar.

### Corregido (tras la revisión)
- El error de importación de un código se muestra en la ventana de importación.
- Un mazo con una carta desaparecida se abre y se edita; el jugador se entera si el archivo de mazos estaba dañado (se guarda una copia).
- Se importan códigos de mazo con otras imágenes de héroe (Magni, Medivh, etc.) y códigos de texto con título en la primera línea.
- El mazo se guarda tras cada cambio, y no solo con el botón «Done».

## [0.2.0] - 2026-10-11

### Añadido
- Menú principal, elección de clase para entrenar, mazos básicos de las nueve clases.
- Mesa de juego: héroes, poderes de héroe, armas, secretos, mesas, manos, maná; mulligan, Elige uno, elección de Rastrear, pantalla de fin de partida.
- Control con el ratón: carta → opción → lugar en la mesa → objetivo; ataque; poder de héroe; pista con carta ampliada.
- Efectos sencillos: números emergentes de daño y curación, sombra del esbirro caído, sacudida de pantalla ante daño fuerte.
- Bot de entrenamiento: prueba acciones sobre una copia de la partida y elige la mejor.
- Historial de turnos durante la partida: todos los turnos desde el principio, sin límite de longitud; las cartas robadas por el rival están ocultas.
- Mesa de depuración: escenario en JSON, búsqueda de carta y adición a la mano, a la mesa o al mazo; partida contra el bot o por ambos bandos; botón «Posición → JSON».

### Corregido (tras la revisión)
- Se puede colocar un esbirro entre otros haciendo clic en el esbirro contiguo.
- El historial no muestra al rival las cartas descartadas por Rastrear.
- La mesa de depuración informa de tipos de campo erróneos en el escenario y no inicia una partida rota.
- Rendirse requiere confirmación.
- El bot piensa más rápido en posiciones grandes.

### Corregido
- El secreto cuenta como hechizo: lo ven Vermis de maná, Archimago Antonidas, Piromántico salvaje, Subastador de Gadgetzan, Profesora violeta, Adicta al maná; Contrahechizo cancela el secreto.
- Demencia oscura: el esbirro robado puede atacar aunque hubiera atacado en el turno anterior de su dueño.
- Rastrear no descarta cartas que el jugador no ha visto.
- Mulligan: el resultado no depende del orden en que los jugadores confirmaron su elección (importante para las partidas en línea).
- Se puede rendirse en cualquier momento, también durante el turno del rival y durante el mulligan.
- Los escenarios conservan el coste de las cartas en la mano, el estado del héroe y el contador de esbirros jugados; un error en el escenario da un mensaje, no un fallo.
- Engendro de luz no depende del orden de las auras; Embozo no quita el Sigilo propio del esbirro; Trampa con culebras no se activa con la mesa llena.
- Una acción incorrecta (por ejemplo, de la red) se rechaza sin cambiar el estado.

## [0.1.0] - 2026-10-11

### Añadido
- Esqueleto del proyecto Godot 4.7 y ejecutor de pruebas.
- Datos de 382 cartas coleccionables del formato Classic (junio de 2014), fichas y cartas del tutorial en 14 idiomas.
- Motor: inicio de partida, mulligan, La moneda, turno, maná, Sobrecarga, Fatiga, quema de cartas, deshielo de Congelado.
- Motor: historial completo de la partida (`history`): cada acción y todos sus eventos desde el inicio.
- Motor: jugar cartas, Grito de batalla, Combo, Elige uno, secretos, armas, ataques, Provocar, Sigilo, Viento furioso, poder de héroe, lista de acciones legales.
- Motor: escenarios: montar cualquier posición desde JSON y guardar la posición actual en JSON (base de la mesa de depuración).
- Cartas: poderes de héroe de las 9 clases, ¡INFIERNO!, Púa mental, Despedazamiento mental, La moneda.
- Cartas: neutrales Basic (43).
- Cartas: neutrales Classic COMMON (40).
- Cartas: neutrales Classic RARE (36).
- Cartas: neutrales Classic EPIC (11).
- Cartas: neutrales legendarias, de recompensa y de promoción (27) y sus fichas: Plátanos, cartas Dream, Power Chord, inventos de Gelbin, Tótem sanador.
- Cartas: Druida (25) y variantes de Elige uno.
- Cartas: Cazador (25), secretos de cazador, Rastrear.
- Cartas: Mago (25), secretos de mago.
- Cartas: Paladín (25), secretos de paladín.
- Cartas: Sacerdote (25).
- Cartas: Pícaro (25), Combo.
- Cartas: Chamán (25), Sobrecarga.
- Cartas: Brujo (25), Lord Jaraxxus.
- Cartas: Guerrero (25). Las 382 cartas coleccionables del formato Classic están implementadas.
- Comprobación de completitud: cada carta con efecto tiene su gancho; 1000 partidas aleatorias sin errores; el motor funciona en la compilación web, el hash coincide con el nativo.
