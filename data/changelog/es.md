# Registro de cambios

Formato: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Versiones: [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.28.4] - 2026-10-24

### Corregido
- Android: el juego ya no se queda colgado en la pantalla de inicio. La compilación comprimía los juegos integrados (paquetes) dentro del APK y Android tardaba minutos en leerlos; ahora se guardan sin comprimir y el juego se abre en pocos segundos.
- Navegador: Ctrl+V (Cmd+V) en un campo de texto pega lo que hay ahora en el portapapeles. Antes, el primer pegado daba el contenido anterior (o nada), por ejemplo con una contraseña copiada de un gestor de contraseñas.
- Android: el campo de la contraseña está marcado como contraseña, así el teclado y el gestor de contraseñas pueden ofrecer la guardada; la dirección del servidor usa un teclado de direcciones.

## [0.28.3] - 2026-10-24

### Corregido
- Android: la biblioteca de reglas del juego está compilada para páginas de memoria de 16 KB (teléfonos con Android 15 o posterior). Esos teléfonos abrían el juego en modo de compatibilidad o no lo abrían.
- Ya no hay servidor por defecto: el juego arranca y se juega sin servidor; añade uno más tarde en Ajustes → Servidores de juego (o con el botón del servidor en Partida en línea).

## [0.28.2] - 2026-10-23

### Añadido
- Un nuevo conjunto de imágenes para Classic, «Pintado simple»: las 534 cartas como ilustraciones pintadas con muy pocos detalles. Elígelo en Juegos → Classic 2014 → Imágenes de cartas (o en los ajustes).

## [0.28.1] - 2026-10-19

### Añadido
- Un nuevo conjunto de imágenes para Classic, «Dibujos 2D»: las 534 cartas en un estilo de dibujos animados plano. Elígelo en Juegos → Classic 2014 → Imágenes de cartas (o en los ajustes).

## [0.28.0] - 2026-10-16

### Añadido
- Un juego nuevo, Neonfall: ciberpunk en la inundada Vesper Arc. Tres campeones (Iris Null, Mother Rust, Director Vale), 60 cartas nuevas, su propio arte, sonidos, música, fuentes y un estilo neón. Es el juego por defecto del servidor.
- Una pantalla «Juegos»: elegir el juego, sus conjuntos de arte, sonidos y música, añadir tu propio juego desde un archivo .cardpack (también en el navegador), borrar los descargados.
- En el juego directo con códigos, un amigo puede enviarte un juego que te falta: consentimiento, transferencia con progreso, comprobación de integridad.
- Varios servidores de juego en los ajustes, cada uno con su sesión y sus amigos. Entrar en la misma cuenta en otro sitio cierra la sesión anterior («Iniciaste sesión en otro dispositivo»).
- El servidor reparte juegos: colas, rangos y Arena por juego; una partida amistosa en el juego propio de un amigo, descargado con consentimiento.
- Una comprobación de la firma de Android: python3 tools/android_keystore_check.py abre una página que comprueba los secretos de GitHub y crea una clave nueva.

### Cambiado
- El motor ya no sabe nada de Hearthstone: todo el juego —reglas, cartas, su lógica en un Lua pequeño, textos, arte, sonidos, rangos, temporizadores— está en un .cardpack. Classic 2014 pasó a ser un paquete así y se comprobó con 7833 partidas grabadas: los resultados coinciden bit a bit.
- El protocolo del juego directo es la versión 3: las versiones anteriores no pueden jugar con esta.

## [0.27.1] - 2026-10-15

### Corregido
- Las versiones de Windows y Linux vuelven a arrancar: el módulo de reglas ahora va junto al juego. Windows es un .zip (ClassicHS.exe con el .dll al lado); el AppImage lo lleva dentro. Las imágenes de la documentación ya no acaban en el juego.

## [0.27.0] - 2026-10-15

### Añadido
- Servidor de juego: un nuevo vestíbulo al estilo del juego — cajas de mazos con los héroes, un selector Normal/Clasificatoria, la medalla de rango con estrellas, un gran botón Jugar; la Arena con la entrada, grandes retratos de héroes, el draft y la pantalla de la racha hasta 12 victorias.
- El inicio de sesión en el servidor se recuerda: el juego entra solo al arrancar. Mientras estás conectado, cada pantalla tiene un botón de amigos: quién está en línea, buscando o jugando, solicitudes, ventanas de chat sobre el juego e invitaciones que puedes aceptar desde cualquier lugar.
- Un nuevo panel de administración del servidor: un panel en vivo, un registro de eventos con filtros (inicios de sesión, mensajes, jugadas, errores), partidas con sus jugadas en tiempo real, cuentas, conversaciones; temas oscuro y claro.

### Cambiado
- Todas las reglas del juego viven ahora en un solo módulo en Rust: funciona dentro del juego en todas las plataformas (como WebAssembly en el navegador) y en el servidor; la ventana del juego solo dibuja. Las reglas se comprobaron con 7833 partidas grabadas: los resultados coinciden con el motor anterior bit a bit.
- Partidas por el servidor: el servidor lleva la partida y envía a cada uno solo lo que puede ver — las cartas ocultas del rival nunca llegan a tu ordenador. El temporizador del turno corre en el servidor; tras un corte de conexión puedes volver a la partida.
- Juego directo con códigos: ambos juegos comprueban cada jugada; si difieren, la partida termina para los dos con el mensaje «algo no cuadra» (no se banea a nadie). Las versiones anteriores no pueden jugar con esta.

## [0.26.1] - 2026-10-15

### Corregido
- En el juego descargado para Windows, macOS, Linux y Android, «Partida en línea» ahora funciona: ahí se puede jugar por un servidor de juego. El juego directo con códigos sigue solo en la versión del navegador.

## [0.26.0] - 2026-10-15

### Añadido
- Un servidor de juego (experimental, opcional): Partida en línea → «Por un servidor de juego». Una cuenta con contraseña, partidas normales y clasificatorias (los 25 rangos de 2014 y Leyenda, estrellas, una temporada nueva cada mes; una puntuación oculta busca un rival parejo), la Arena hasta 12 victorias o 3 derrotas, amigos por etiqueta, mensajes, invitaciones a una partida amistosa y bloqueo. El servidor comprueba cada jugada con las reglas del propio juego. La dirección del servidor está en Ajustes → «Servidor de juego» (ws://localhost:7377 por defecto). El servidor (Rust, carpeta server/) no está alojado en ningún sitio: lo ejecutas tú; cada versión incluye el servidor para Windows, macOS y Linux. El juego directo con códigos sigue igual.

## [0.25.1] - 2026-10-15

### Corregido
- Los secretos del rival se muestran en la parte superior de su retrato, como los tuyos (antes, debajo).

## [0.25.0] - 2026-10-15

### Añadido
- Compilaciones para todas las plataformas: cada versión tiene una publicación en GitHub con el juego para Windows (.exe), Linux (.AppImage), macOS (.zip), Android (.apk) y la versión web (.zip). El sitio enlaza: «Descargar el juego».

## [0.24.1] - 2026-10-12

### Cambiado
- Los mazos básicos salen de las listas de mazos: cada clase tiene un mazo clásico. Un mazo básico aparece solo para una clase sin mazo clásico (ahora ninguna). Los mazos básicos sin cambios salen una vez de los mazos guardados; los cambiados se quedan.

## [0.24.0] - 2026-10-12

### Añadido
- Ajustes → Conjunto musical: generada o libre (CC0) — música de taberna medieval de RandomMind: «Minstrel Dance» en el menú, «The Old Tower Inn», «King's Feast» y «The Bard's Tale» en la partida. Los sonidos siguen siendo los generados.

## [0.23.3] - 2026-10-12

### Cambiado
- El mulligan como en el original: las cartas elegidas vuelan al mazo, las nuevas ocupan su lugar y se quedan delante de ti («Esperando al rival…»); cuando el rival ha elegido, al segundo jugador le aparece la Moneda al lado, luego todas las cartas bajan a la mano en el mismo orden y solo entonces se roba la carta del primer turno. La mano bajo la pantalla de mulligan no se muestra.
- El botón del rastreador de mazo está bajo el botón del menú y ya no tapa los cristales de maná del rival.

## [0.23.2] - 2026-10-12

### Cambiado
- Una carta con Combo jugable en la mano brilla en amarillo en vez de verde cuando ya se jugó una carta este turno (su Combo se activará).
- La Moneda siempre llega con su propia animación — gira con luz dorada y va a la mano —, también cuando el rival terminó el mulligan más tarde, y para los dos jugadores.

## [0.23.1] - 2026-10-12

### Corregido
- El botón que silencia al rival muestra el estado: «Silenciar», y «Activar sonido» mientras el rival está silenciado.

## [0.23.0] - 2026-10-12

### Cambiado
- Mulligan: tras «Confirmar», las cartas nuevas llegan a la mano al momento, sin esperar al rival, y ocupan el lugar de las cambiadas — la mano conserva el orden de la pantalla de mulligan; luego «Esperando al rival…». En línea todo sigue sincronizado: el barajado del mulligan usa el flujo aleatorio propio de cada jugador.
- El temporizador del mulligan en línea no tiene mecha: en los últimos 10 segundos aparecen números rojos bajo «Confirmar».
- Lo que señala el rival ya no apaga tu propio brillo: el verde o el amarillo se mantiene, con un leve anillo rojo por fuera.
- Una carta quemada por mano llena arde solo con el shader, sin los triángulos que suben.

## [0.22.0] - 2026-10-12

### Añadido
- Una cola de órdenes: la siguiente jugada se puede dar sin esperar a que termine la animación anterior — jugar una carta, atacar, usar el poder de héroe, terminar el turno. Las órdenes esperan en cola (marcadas en amarillo) y se cumplen de una en una tras las animaciones, en orden; si una orden es posible se comprueba después de las que ya esperan. Si una orden se vuelve imposible (el turno terminó), la cola se cancela con un aviso. El tutorial no tiene cola.

### Cambiado
- La mecha del turno arde sin la línea punteada de ceniza detrás.

## [0.21.1] - 2026-10-12

### Cambiado
- Partida en línea: todo lo que señala el rival brilla en rojo — esbirros, héroes, poderes de héroe, armas, secretos y la carta levantada en su mano (antes solo los esbirros, en blanco).

## [0.21.0] - 2026-10-12

### Añadido
- Reglas de la Arena: antes de los héroes, el anfitrión elige para ambos «Un mazo para toda la Arena» o «Un mazo nuevo en cada partida»; el segundo tiene un ajuste «Los jugadores pueden conservar su mazo en vez de elegir de nuevo». Si está activo, tras cada partida cada uno elige «Armar un mazo nuevo» o «Conservar mi mazo», y el rival ve que el jugador está decidiendo. El invitado espera la elección y ve las reglas; el marcador se ve durante una nueva selección.

### Cambiado
- Arena: las cartas legendarias salen el doble (2 % en una elección normal, 8 % en las elecciones 1, 10, 20 y 30), las épicas una vez y media más (7,5 % y 27 %).

## [0.20.1] - 2026-10-12

### Cambiado
- Las imágenes del resultado están comprimidas: la descarga vuelve a unos 61 MB (64 MB en 0.20.0).

## [0.20.0] - 2026-10-12

### Añadido
- La Arena con un amigo en línea: Partida en línea → Arena. Cada uno toma uno de tres héroes y arma 30 cartas como en la Arena de 2014: tres cartas de una rareza por elección (básicas y comunes cuentan como una), rara o mejor en las elecciones 1, 10, 20 y 30, cartas de clase una vez y media más frecuentes, sin límite de copias. La lista del mazo a la derecha, la curva de maná abajo a la izquierda, el progreso del rival arriba a la derecha (héroe elegido o no, cartas, listo; nunca el héroe ni las cartas). Cuando los dos pulsan «Listo», empieza una serie a tres victorias; tras cada partida, el vestíbulo con el marcador; se puede rendirse en la Arena o salir al menú en cualquier momento.
- El resultado de una partida desde tu lado — ¡Victoria!, Derrota o Empate — sobre una imagen semitransparente (en línea antes decía «Gana el jugador N»).

### Comprobado
- Empate: un Fuego infernal que mata a los dos héroes da empate, y los dos héroes se hacen añicos.

## [0.19.5] - 2026-10-12

### Corregido
- Sitio: la sección de código abierto mostraba «{tests}» en lugar del número de pruebas.

## [0.19.4] - 2026-10-12

### Añadido
- Un enlace al sitio en Telegram, WhatsApp, Discord, Slack y otras mensajerías muestra una vista previa con la captura principal del juego (una partida), el título y una descripción.

## [0.19.3] - 2026-10-12

### Añadido
- Sitio: la versión del juego y un bloque «Novedades» (las últimas entradas del registro en el idioma de la página), una sección «En la partida», preguntas y respuestas (requisitos, móviles, dónde se guardan los mazos, jugar sin conexión, instalar como aplicación, qué envía el juego en línea, cómo informar de un error), una sección de código abierto; el enlace al registro abre el idioma de la página; en el móvil la página ya no se desplaza de lado.

## [0.19.2] - 2026-10-12

### Cambiado
- El sitio y el README coinciden con el juego: entrenamiento con elección de mazo y héroe del bot, diez mazos Classic famosos, el repetidor del juego en línea, herramientas de depuración en Ajustes, emoticonos con las palabras de los héroes, juegos de ilustraciones y reversos; los pasos en línea usan los nombres de los botones del juego; se quitan afirmaciones viejas (ningún servidor, todo el arte dibujado por código).

## [0.19.1] - 2026-10-12

### Cambiado
- Sitio: capturas nuevas (historial por turnos, rastreador de mazo, lecciones antes de las misiones, herramientas de depuración; la página rusa muestra capturas en ruso), textos al día y tamaño de la descarga (unos 61 MB). En el móvil, un toque amplía una carta del abanico y un doble toque le da la vuelta.

## [0.19.0] - 2026-10-12

### Añadido
- En el primer arranque el juego pide elegir el idioma; el del sistema aparece resaltado.

## [0.18.5] - 2026-10-12

### Cambiado
- El daño aleatorio a varios objetivos (Misiles Arcanos, Ira vengativa, Bombardero loco, Disparo múltiple, Relámpago bifurcado, etc.) vuela proyectil a proyectil; la salud del objetivo baja con cada impacto.

## [0.18.4] - 2026-10-12

### Añadido
- Esquivo: el esbirro está envuelto en una neblina dorada que brilla, y la palabra tiene su ventanita (hechizos y poderes de héroe no pueden elegirlo como objetivo).

## [0.18.3] - 2026-10-12

### Añadido
- Las cartas quemadas (mano llena) y el daño por fatiga aparecen en el historial de la izquierda: una casilla propia con imagen y explicación al pasar el ratón.

### Corregido
- Tutorial: no se puede atacar al Cronista Cho mientras tenga esbirros.

## [0.18.2] - 2026-10-12

### Cambiado
- Se quitó la síntesis de voz: el juego ya no lee en voz alta nombres ni emoticonos; se quitaron los ajustes Voz y Habla. Las frases de los héroes salen como texto en bocadillos con la punta hacia el héroe.

### Corregido
- Una casilla marcada perdía su fondo bajo el ratón.

## [0.18.1] - 2026-10-12

### Añadido
- Editor de escena: zonas de Secretos y Arma, elegir quién juega primero y fichas en la lista de cartas.

## [0.18.0] - 2026-10-12

### Cambiado
- Las herramientas de depuración pasaron a los ajustes y son una pantalla con pestañas: «Escena» (montar una escena con el ratón: héroes, maná, daño, armadura, mano, tablero, mazo; el JSON al lado; el modo con botones de opción), «Prueba de interacciones» (escenarios listos para cada una de las 534 cartas, 1108 en total: eliges carta y escenario y se juega en una partida real con todos los efectos y sonidos), «Prueba de cartas» y «Prueba de efectos».

## [0.17.1] - 2026-10-12

### Añadido
- Al perder, el retrato del héroe estalla en pedazos.
- Los símbolos de rayo y veneno están quietos y destellan con un sonido suave cuando se activa su efecto.

### Corregido
- Tutorial: «Siguiente misión» abre las explicaciones en una pantalla propia; la pantalla de recompensa ya no bloquea.

## [0.17.0] - 2026-10-12

### Añadido
- El historial de la izquierda está separado por turnos («Turno N» en el color del jugador); al pasar el ratón sobre una acción se ve qué hizo y a quién: daño, sanación, mejoras, congelación, silencio, muertes, invocaciones, armas equipadas y los gritos de batalla y últimos alientos que desencadenó. Las cartas ocultas del rival siguen ocultas.
- El rastreador de mazo tiene su propio botón junto al menú: «Tu mazo» con imágenes, ×2, cartas agotadas atenuadas y la probabilidad de robar cada carta; «Jugado por el rival», una lista que crece con ×2.

## [0.16.2] - 2026-10-12

### Corregido
- Tutorial: tras una victoria, «Siguiente misión» abría las explicaciones bajo la pantalla de recompensa y la pantalla se bloqueaba.

## [0.16.1] - 2026-10-12

### Añadido
- Bajo el botón «Fin de turno»: el tiempo de partida y, en línea, el tiempo que queda del turno.
- Todo lo de la mesa se ilumina bajo el ratón; un arma se da la vuelta cuando no es el turno de su héroe.
- Esbirros y héroes dicen sus frases (al jugarse, atacar, morir, emoticonos, inicio de partida, rendirse) cuando hay grabación; los emoticonos de los héroes, con sus propias palabras.

### Cambiado
- La mecha del temporizador es un cordel trenzado con una brasa, chispas y humo.
- Una carta quemada arde desde los bordes con un borde incandescente.
- Un golpe al héroe: número de daño más grande; más de 5 de daño sacude más fuerte con un sonido grave.
- Un héroe que puede atacar brilla más.

## [0.16.0] - 2026-10-11

### Añadido
- Menú principal: Jugar abre un submenú con juego en línea, entrenamiento y tutorial.
- Entrenamiento por pasos: elegir un mazo de una lista con retratos de héroes (o ir a los mazos), luego el rival en una cuadrícula de 3×3, luego Jugar.
- Juego en línea por pasos: nombre, mazo, Crear partida o Unirse; los códigos tienen un botón Copiar al lado.
- Tutorial: misiones con los retratos de los jefes; antes de cada misión, explicaciones ilustradas de sus nuevos conceptos (partes de una carta, combate, maná, hechizos, grito de batalla, provocar, cargar, último aliento, poder de héroe, congelar, armas).
- Colección y mazos en una sola pantalla: todas las cartas a la izquierda con pestañas de clase, filtros de tipo, coste, rareza y búsqueda; los mazos a la derecha con copiar, exportar y borrar; un mazo se edita en el mismo sitio.

### Corregido
- Juego en línea: un repetidor TURN para redes sin camino directo; el invitado espera hasta 4 minutos la respuesta del anfitrión y renueva los candidatos de conexión todo ese tiempo (antes el navegador se rendía a los pocos segundos).

## [0.15.3] - 2026-10-11

### Añadido
- La pantalla de carga muestra la versión del juego.

## [0.15.2] - 2026-10-11

### Cambiado
- Los emblemas de clase son simples y planos; la espada de la gema de ataque es más corta, apunta arriba a la derecha y se ve la empuñadura abajo a la izquierda; el rayo bajo el retrato es la mitad de grande; el frasco de veneno es verde, más pequeño y quieto.
- Silencio: cintas rosas brillantes rodean el retrato.
- Último aliento: la calavera crece desde el esbirro y sube.
- Un esbirro con grito de batalla primero ocupa su sitio y luego la flecha al objetivo sale de él; el clic derecho o llevar la flecha de vuelta a la mano cancela, y la carta vuelve a la mano.

### Corregido
- Las chispas de daño con hechizos a veces se detenían.

## [0.15.1] - 2026-10-11

### Cambiado
- Las gemas de maná, salud, ataque, armadura y durabilidad son más pequeñas y lisas en el centro para leer mejor los números; las marcas bajo el retrato son más pequeñas.

## [0.15.0] - 2026-10-11

### Añadido
- Imágenes de interfaz pintadas: cristal de maná, gota de salud, gema de ataque con espada, escudos de armadura y durabilidad, escudo de Provocar, calavera y huesos, frasco de veneno, rayo, emblemas de clase, una imagen para la fatiga.
- Los esbirros venenosos (Cobra emperador, Asesina paciente) llevan un frasco de veneno.
- Una ventanita de palabra clave para Enfurecer.
- La carta de un esbirro silenciado muestra su texto tachado con una cruz roja al pasar el ratón.
- La sobrecarga se ve enseguida: candados naranjas sobre los cristales para el próximo turno; un cristal bloqueado muestra un candado en vez de una cruz.
- Una carta creada por una carta en la mesa (Archimago Antonidas, Ysera) vuela desde ella a la mano.

### Cambiado
- Los brillos (jugable, seleccionado, objetivo) quedan siempre fuera de todos los efectos de una carta.
- Viento furioso: ráfagas en una órbita inclinada, por detrás y por delante de la carta.
- Sigilo: una neblina a través de la que se adivina la imagen; Congelado: una capa de escarcha y un borde helado.
- Los secretos sobre el retrato del héroe son redondos: morados para el mago, verdes para el cazador, amarillos para el paladín.
- Las gemas de rareza son redondas, con sombra y brillo.
- El dragón de un esbirro legendario cubre solo la parte superior del óvalo.

## [0.14.1] - 2026-10-11

### Cambiado
- El dragón de un esbirro legendario en la mesa se enrosca alrededor del óvalo del retrato.

### Corregido
- En el navegador, el primer Cmd/Ctrl+V no pegaba nada en lugar del código copiado (código de un amigo, importar mazo).
- Juego en línea: el tiempo con la pestaña oculta ya no corta la espera de la conexión.
- Una carta de la mano se puede coger pulsando bajo la carta levantada, donde estaba.
- Las ventanitas de palabras clave vuelven a aparecer al pasar sobre una carta de la mano.

## [0.14.0] - 2026-10-11

### Añadido
- 10 mazos clásicos listos en el menú de mazos: Control Warrior, Midrange Shaman, Midrange Druid, Control Priest, Miracle Rogue, Midrange Paladin, Handlock, Freeze Mage, Midrange Hunter, Zoolock. Los jugadores con mazos guardados los reciben una vez.

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
