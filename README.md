# Thesito Addon

Addon para **World of Warcraft: Forever** (cliente 1.60.1) con todo lo que necesitas mientras subes de nivel, en una sola ventana y en castellano.

Detecta solo la clase, la raza, la facción y las profesiones de cada personaje, así que a cada uno le sale lo suyo.

## Qué hace

| Pestaña | Para qué sirve |
|---|---|
| **Talentos** | La ruta de talentos más recomendada para subir solo con tu clase. Se ve como el árbol del juego, con lo que ya tienes, el siguiente talento y lo que pondrás después. El siguiente brilla también en la ventana de talentos del juego. |
| **Instructor** | Al hablar con el instructor de tu clase, te dice qué hechizos son esenciales, cuáles útiles y cuáles te puedes saltar para ahorrar oro. |
| **Bolsas** | Qué puedes vender o tirar (basura, objetos de misiones ya hechas, libros ya aprendidos), qué desencantar, qué guardar para tus profesiones y qué libros de biblioteca entregar. Con el botón **Ordenar bolsas** (también en la ventana de las bolsas, la del juego o la de Bagnon) junta los montones y agrupa: misiones, piedra de hogar y consumibles, bolsas, equipo, tus profesiones, otras profesiones, lo demás, para desencantar y, al final, lo de vender o tirar. Cada sección empieza en una fila nueva si hay sitio; si no, deja una casilla vacía entre secciones. |
| **Ventana de bolsas** | Sustituye a la ventana de bolsas del juego (tecla B, vendedor, banco...): tus cosas por secciones (misiones, consumibles, equipo, profesiones, para vender...), con buscador, secciones plegables y la explicación de Thesito al pasar el ratón. Con el botón *Por bolsas* / *Por secciones* cambias a ver cada bolsa por separado, como la del juego. Tiene en cuenta las bolsas especiales (de hierbas, de encantamiento...) y la de componentes. El botón **Liberar casilla** borra (o vende, con un vendedor abierto) lo que menos vale de «Para vender o tirar», siempre preguntando antes; con clic derecho abre DeleteCheapestItem si lo tienes. Clic derecho, vender, arrastrar y partir montones funcionan como siempre. Se activa sola si no usas otro addon de bolsas (Bagnon, Baganator...); se cambia con la casilla *Ventana propia* de la pestaña Bolsas. |
| **Misiones** | Tus misiones con su nivel en el color de su dificultad (gris, verde, amarillo, naranja, rojo) y su tipo: **E** élite, **D** mazmorra, **R** banda, **P** JcJ. Qué hacer, dónde y a quién entregarlas. Pone rumbo y te dice paso a paso cómo llegar por el camino más rápido, combinando a pie, los vuelos que ya conoces y los zepelines y barcos. Dibuja la ruta entera en el mapa (morado a pie, dorado en vuelo, azul en zepelín o barco) y la línea del minimapa y la flecha te llevan a la siguiente parada. Si tienes **SendaFH** con su navegación, los tramos a pie van por los caminos y los pasos, sin subir montañas. |
| **Importante** | Misiones que dan bolsas grandes, premios especiales al final de una cadena de misiones (como el *Saco de dormir acogedor*: cuántas te faltan y cuál es la siguiente), misiones de tu clase, recompensas que mejoran tu equipo y, si eres Sastre, las bolsas que puedes coser. |

**Otros jugadores con Thesito:** no escribe nada en ningún chat. Los addons se comunican entre ellos por un canal invisible: el Thesito de los jugadores de tu hermandad, de tu grupo y de tus amigos conectados (del juego o de Battle.net) se dicen qué versión tienen (solo eso). Así ves en Opciones (o con `/thesito quien`) quién más lo usa, y te sale un aviso si alguien tiene una versión más nueva. No se guarda nada y se apaga en Opciones.

Todo se puede quitar en **Opciones** (botón junto a *Créditos*): cada pestaña, la ventana de bolsas, el botón de ordenar, el aviso al subir de nivel, el brillo en la ventana de talentos, abrir con el instructor y el botón del minimapa. Se guarda para cada personaje.

Clases con ruta de talentos y consejos de instructor: **todas** (guerrero, paladín, cazador, pícaro, sacerdote, chamán, mago, brujo y druida).

## Instalación

1. Descarga el último zip desde **[Releases](../../releases/latest)** (archivo `ThesitoAddon-vX.Y.Z.zip`, en *Assets*).
2. Cierra el juego.
3. Descomprime el zip y copia la carpeta **`ThesitoAddon`** en:
   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```
   Tiene que quedar `...\AddOns\ThesitoAddon\ThesitoAddon.toc` (no una carpeta dentro de otra).
4. Abre el juego. En la pantalla de personajes pulsa **AddOns** y comprueba que **Thesito Addon** está marcado.
5. Dentro del juego: botón del minimapa o escribe `/thesito`.

### Que se actualice solo (WowUp)

Con la app **[WowUp](https://wowup.io)** (Windows y Mac; en un Mac con procesador Intel, descarga su versión Intel) no tienes que volver a bajar el zip:

1. Abre WowUp y elige arriba la instalación de **Forever**.
2. Pulsa **Get Addons** → **Install from URL** y pega `https://github.com/JulianSa/ThesitoAddon`.
3. Cada vez que salga una versión nueva, WowUp te la ofrece en *My Addons*, como el resto de tus addons.

### Addons recomendados

Instálalos con la app de CurseForge eligiendo *World of Warcraft: Forever*:

- **Questie**: necesario para Misiones e Importante, y para saber de qué misión es cada objeto.
- **TomTom**: la flecha y las líneas del mapa y el minimapa.
- **SkillUpForever** (opcional): solo para las bolsas que puede coser un Sastre.
- **SendaFH** (opcional), con su navegación (*SendaFH Nav*): para que el rumbo a pie vaya por los caminos en vez de en línea recta. Se puede apagar en Opciones.

Sin ellos el addon funciona, pero esas partes avisan de que faltan.

## Comandos

| Comando | Qué hace |
|---|---|
| `/thesito` | Abre o cierra la ventana |
| `/thesito talentos` · `instructor` · `bolsas` · `misiones` · `importante` · `creditos` | Abre esa pestaña |
| `/thesito opciones` | Abre las opciones |
| `/thesito quien` | Quién más tiene Thesito en tu hermandad, tu grupo o tus amigos, y con qué versión |
| `/thesito mochila` | Abre o cierra las bolsas (igual que la tecla B) |
| `/thesito centrar bolsas` | Vuelve a poner la ventana de bolsas en su sitio |
| `/thesito ordenar` | Ordena las bolsas por grupos |
| `/thesito liberar` | Borra o vende lo que menos vale de «Para vender o tirar» (pregunta antes) |
| `/thesito quitar` | Quita el rumbo del mapa |
| `/thesito mapa` | Si la ruta no se ve en el mapa grande, dice por qué |
| `/thesito centrar` | Vuelve a poner la ventana en el centro |
| `/thesito debug` | Datos para revisar si algo falla |

## Créditos

- **[Questie / QuestieDB](https://github.com/Questie/Questie)** (GPLv3): datos de misiones, PNJ, objetos y zonas, consultados mientras juegas.
- **SkillUpForever** (GPLv3): datos de recetas de profesiones, consultados mediante su API pública.
- **TomTom** y **HereBeDragons**: flecha y posiciones en el mapa.
- **[Icy Veins](https://www.icy-veins.com/wow-forever/)** (noviembre de 2026): rutas de talentos para subir solo de todas las clases, sacadas de sus guías de subida:
  - Sacerdote Sombras ([Anshlun](https://www.icy-veins.com/wow-forever/shadow-priest-leveling)), con un cambio propio al nivel 26 (*Explosión mental mejorada* 5/5 en vez de *Enfoque de las Sombras* 1/5). Comparada con las guías de Wowhead, WoW Forever Builds, WoW Handbook y Forever Hispano.
  - Guerrero Armas ([Abide](https://www.icy-veins.com/wow-forever/arms-warrior-leveling)) · Paladín Reprensión ([Meyra](https://www.icy-veins.com/wow-forever/retribution-paladin-leveling)) · Cazador Dominio de bestias ([Impakt](https://www.icy-veins.com/wow-forever/beast-mastery-hunter-leveling)) · Pícaro Combate ([Sellin](https://www.icy-veins.com/wow-forever/combat-rogue-leveling)) · Mago Escarcha ([Teloril](https://www.icy-veins.com/wow-forever/frost-mage-leveling)) · Brujo Aflicción ([Abide](https://www.icy-veins.com/wow-forever/affliction-warlock-leveling)) · Druida Feral ([Meyra](https://www.icy-veins.com/wow-forever/feral-druid-leveling)) · Chamán Mejora ([Wordup](https://www.icy-veins.com/wow-forever/enhancement-shaman-leveling)).
- **SendaFH** (GPLv3): identificadores de los talentos de Forever.
- **SendaFH Nav** (GPLv3, Forever Hispano), cuyo cálculo de rutas parte del de **[Shortest Path Forever](https://github.com/cjber/shortest-path-forever)** (Cillian Berragan): si lo tienes instalado, Thesito le pide los caminos a pie mientras juegas. Thesito no incluye su código ni sus mapas.
- **Warcraft Wiki** y **Warcraft Tavern**: documentación de la API y de los libros de biblioteca.
- Consultado (sin copiar su código): **Bagnon**, para saber cómo sustituir la ventana de bolsas del juego, y **SkillUpForever**, para saber cómo da Forever las profesiones.
- Consejos de instructor, pesos de estadísticas y posiciones de zepelines y barcos: criterio propio (editables en `Data.lua` y `Nav.lua`).

Hecho por Thesito con ayuda de Claude (Anthropic). Si algo de esto es tuyo y quieres que se cambie, abre una *issue*.

## Licencia

[GPLv3](LICENSE).
