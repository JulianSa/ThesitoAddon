# Thesito Addon

Addon para **World of Warcraft: Forever** (cliente 1.60.1) con todo lo que necesitas mientras subes de nivel, en una sola ventana y en castellano.

Detecta solo la clase, la raza, la facción y las profesiones de cada personaje, así que a cada uno le sale lo suyo.

## Qué hace

| Pestaña | Para qué sirve |
|---|---|
| **Talentos** | La ruta de talentos más recomendada para subir solo con tu clase. Se ve como el árbol del juego, con lo que ya tienes, el siguiente talento y lo que pondrás después. El siguiente brilla también en la ventana de talentos del juego. |
| **Instructor** | Al hablar con el instructor de tu clase, te dice qué hechizos son esenciales, cuáles útiles y cuáles te puedes saltar para ahorrar oro. |
| **Bolsas** | Qué puedes vender o tirar (basura, objetos de misiones ya hechas, libros ya aprendidos), qué desencantar, qué guardar para tus profesiones y qué libros de biblioteca entregar. |
| **Misiones** | Tus misiones con qué hacer, dónde y a quién entregarlas. Pone rumbo con una línea en el mapa y el minimapa, por etapas: zepelín o barco, vuelo y a pie. |
| **Importante** | Misiones que dan bolsas grandes, misiones de tu clase, recompensas que mejoran tu equipo y, si eres Sastre, las bolsas que puedes coser. |

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

### Addons recomendados

Instálalos con la app de CurseForge eligiendo *World of Warcraft: Forever*:

- **Questie**: necesario para Misiones e Importante, y para saber de qué misión es cada objeto.
- **TomTom**: la flecha y las líneas del mapa y el minimapa.
- **SkillUpForever** (opcional): solo para las bolsas que puede coser un Sastre.

Sin ellos el addon funciona, pero esas partes avisan de que faltan.

## Comandos

| Comando | Qué hace |
|---|---|
| `/thesito` | Abre o cierra la ventana |
| `/thesito talentos` · `instructor` · `bolsas` · `misiones` · `importante` · `creditos` | Abre esa pestaña |
| `/thesito quitar` | Quita el rumbo del mapa |
| `/thesito centrar` | Vuelve a poner la ventana en el centro |
| `/thesito debug` | Datos para revisar si algo falla |

## Créditos

- **[Questie / QuestieDB](https://github.com/Questie/Questie)** (GPLv3): datos de misiones, PNJ, objetos y zonas, consultados mientras juegas.
- **SkillUpForever** (GPLv3): datos de recetas de profesiones, consultados mediante su API pública.
- **TomTom** y **HereBeDragons**: flecha y posiciones en el mapa.
- **[WoW Forever Builds](https://wowforeverbuilds.com/guide/shadow-priest-leveling)**: ruta de Sacerdote Sombras para subir solo (17/11/2026).
- **[Forever Hispano](https://foreverhispano.com/clases-y-guias/)**: rutas de talentos del resto de clases (guías de clase, revisión 1.1, 07/11/2026).
- **SendaFH** (GPLv3): identificadores de los talentos de Forever.
- **Warcraft Wiki** y **Warcraft Tavern**: documentación de la API y de los libros de biblioteca.
- Consejos de instructor, pesos de estadísticas y posiciones de zepelines y barcos: criterio propio (editables en `Data.lua` y `Nav.lua`).

Hecho por Thesito con ayuda de Claude (Anthropic). Si algo de esto es tuyo y quieres que se cambie, abre una *issue*.

## Licencia

[GPLv3](LICENSE).
