# Auditoría de datos, links y SEO — respiraventas.com.ar

Fecha: 3 de noviembre de 2026. Se revisó la rama `main` en el commit `4833728` («Actualizacion catalogo 01/11/2026 23:32», 4.172 discos).

## Resumen en 30 segundos

- **El sitio está sano en lo estructural.** En las 10.017 páginas no hay ningún link interno roto. Los sitemaps no listan ninguna dirección inexistente ni ninguna página con `noindex`, y tampoco falta en ellos ninguna página indexable. Todas las canónicas son correctas, todas las imágenes tienen `alt` y todos los JSON-LD son válidos.
- **El problema más importante es un bug del generador.** Los artistas escritos con «**Y** Su Orquesta» (con Y mayúscula) no se agrupan con su artista principal. Por eso Osvaldo Pugliese tiene **3 páginas indexables que compiten entre sí**. En total afecta a 67 discos de 32 artistas. Se arregla con una línea, pero va en el generador (ver G1).
- **En este PR se corrigieron a mano solo las páginas que el generador no pisa:**
  - las 6 páginas temáticas;
  - `colecciones.html`;
  - el `<head>` de `index.html`.
- Todo lo que se genera solo (fichas, artistas, décadas, sitemaps, `compilados.html`, `maxis.html`) **no se tocó**: el problema y el cambio que habría que hacer en el generador quedan documentados acá.

---

## 1. Cómo se generan las páginas (antes de corregir nada)

| Qué | Lo genera | ¿Se puede corregir a mano? |
|---|---|---|
| `disco/*.html` (4.250 fichas), `d/*.html` (4.250), `data/vendidos.json` | `_PABLO/Programas/generar-fichas.ps1` (`Sync-Fichas`) | **No**: se reescriben **todas** en cada actualización |
| `artista/*.html` (1.501), `decada/*.html` (5), `compilados.html`, `maxis.html` | `_PABLO/Programas/generar-hubs.ps1` (`Sync-Hubs`) | **No** |
| `sitemap.xml`, `sitemap-paginas.xml`, `sitemap-discos.xml`, `sitemap-hubs.xml` | `Build-Sitemaps`, `Build-SitemapIndice` y `Build-SitemapHubs` | **No** |
| `data/records.json` | `_PABLO/Programas/actualizar.ps1`, a partir del Excel de Drapi | **No** (los datos vienen de Mercado Libre) |
| `index.html` | A mano. El script reemplaza solo el texto «Más de N discos» y el bloque entre `<!-- ENVIOS:INICIO -->` y `<!-- ENVIOS:FIN -->` | Sí, fuera de esas zonas |
| `rock-nacional.html`, `tango.html`, `brasil.html`, `melodico.html`, `folklore.html`, `cumbia-cuarteto.html` | A mano. El script cambia solo el número «4.100+» y el texto «Más de N títulos» | Sí, fuera de esos números |
| `colecciones.html`, `404.html`, `robots.txt` | A mano | Sí |

`.github/workflows/deploy.yml` no genera nada: publica el repositorio completo en GitHub Pages con cada push a `main`. Los generadores corren **en la PC de Pablo** (`actualizar.bat` o `agregar.bat`) y hacen el commit «Actualizacion catalogo …» y el push.

> **Atención operativa (impacto alto):** `actualizar.ps1` hace `git push origin main` **sin hacer antes `git pull`**. Si se mergea **cualquier** PR en GitHub (este u otro de las sesiones paralelas), la próxima actualización desde la PC va a fallar con «No se pudo subir a GitHub». Lo mismo pasa al revés: los cambios del PR no le llegan a la PC. **Después de mergear, hay que correr `git pull` en la carpeta `vinylshop` de la PC antes de la próxima actualización.** La solución de fondo se describe en G10.

---

## 2. Correcciones hechas en este PR (solo páginas hechas a mano)

| # | Cambio | Archivos | Por qué |
|---|---|---|---|
| C1 | **37 nombres de artistas ahora enlazan a su página de artista**: 7 en Tango, 16 en Melódico, 6 en Brasil y 8 en Cumbia y Cuarteto. Solo se enlazaron artistas que tienen una página **indexable** (están en `sitemap-hubs.xml`). El link hereda el color y no se subraya, así que la página **se ve exactamente igual** (verificado en el navegador). | `tango.html`, `melodico.html`, `brasil.html`, `cumbia-cuarteto.html` | Las páginas temáticas, que son las que más autoridad tienen, no enlazaban a **ninguna** página de artista ni a ninguna ficha |
| C2 | **Open Graph completo** (`og:title`, `og:description`, `og:url`, `og:image`, `og:type`, `og:site_name` y `og:locale`) | las 6 páginas temáticas y `colecciones.html` | No tenían **ninguna** etiqueta Open Graph: al compartirlas por WhatsApp o Facebook salían sin imagen y con un título armado al azar |
| C3 | **Datos estructurados** `CollectionPage` + `BreadcrumbList` | las 6 páginas temáticas y `colecciones.html` | No tenían JSON-LD |
| C4 | `index.html`: se agregan `og:image`, `og:site_name` y `og:locale`, y los JSON-LD `WebSite` y `Organization` (nombre, logo, mail, teléfono y Rosario, todos datos que ya están publicados en el sitio). Además, `og:url` pasa a terminar en `/`, igual que la canónica. | `index.html` (solo el `<head>`) | La portada no tenía imagen para compartir ni datos de la tienda |
| C5 | Título de `colecciones.html`: pasa de «Géneros — Respira Ventas» a «Colecciones de vinilos por género, década y edición — Respira Ventas» | `colecciones.html` | El título viejo no describía la página, que también reúne las décadas y los compilados |

Las zonas que reescribe `actualizar.ps1` no se tocaron, y se comprobó que sus patrones siguen encontrando el texto que buscan. Para compartir se usa `assets/logo-icon.jpg` (510×510, 33 KB) y no `logo-full.jpg`, que pesa 687 KB: WhatsApp suele no mostrar imágenes tan pesadas.

---

## 3. Hallazgos ordenados por impacto

### Impacto ALTO

#### G1. Bug del generador: «X Y Su Orquesta» no se agrupa con «X» (67 discos, 32 artistas)

- **Qué pasa:**
  - `Set-MapaCanonico` (en `generar-hubs.ps1`) detecta las colaboraciones con `-match`, que **no distingue** mayúsculas.
  - En cambio, corta el nombre con `[regex]::Split(...)`, que **sí** las distingue.
  - Con «Osvaldo Pugliese **Y** Su Orquesta Típica» el corte no ocurre y el disco queda en un artista aparte.
  - Se reprodujo el algoritmo y da **exactamente** los slugs que hoy tiene `records.json`, así que el diagnóstico está confirmado.
- **Consecuencias:**
  - Osvaldo Pugliese tiene 3 páginas indexables: `osvaldo-pugliese` (17 discos), `…-y-su-orquesta-tipica` (9) y `…-y-su-orquesta` (6).
  - Lo mismo pasa con Aníbal Troilo (8 + 4) y con Armando Pontier, Werner Müller, Nito Mestre, Horacio Salgán, Julio De Caro, Jaime Torres y otros.
  - Google reparte la relevancia entre esas páginas y ninguna posiciona bien.
- **Qué cambiar en el generador** (`generar-hubs.ps1`, dentro de `Set-MapaCanonico`):
  ```powershell
  # antes
  $primero = ([regex]::Split($n, $SEP_COLAB))[0].Trim()
  # después
  $primero = ([regex]::Split($n, $SEP_COLAB, [Text.RegularExpressions.RegexOptions]::IgnoreCase))[0].Trim()
  ```
- **Efecto esperado:**
  - Los 67 discos pasan a la página del artista principal; Pugliese queda con una sola página de 34 discos.
  - Las páginas viejas **no se borran**: quedan con `noindex` y un link «Estos discos ahora los agrupamos junto a…», que es el «Caso 1» ya previsto en el generador.
- Lista completa de agrupaciones (revisada a mano; todas son el mismo artista principal):
  - Alfredo De Angelis, André Kostelanetz, Aníbal Troilo, Antonio Bono, Armando Pontier, Bert Kaempfert, Beto Orlando, Eduardo Tirabassi, Estela Raval, Franck Pourcel (2 variantes), Horacio Salgán (2), Jaime Torres (2), Javier Solís, Juan Ramón, Julio De Caro (2), Leopoldo Federico, Litto Nebbia (2), Malvicino, Marcelo San Juan, Marek Weber;
  - Miguel Cantilo, Nati Mistral, Nito Mestre, Norrie Paramor, Osvaldo Pugliese (3), Paul Mauriat, Pedro Laurenz, Ray Conniff, Ronnie Aldrich, Stanley Black, Vincent Morocco y Werner Müller.

#### G10. `actualizar.ps1` no sincroniza con GitHub antes de subir

Esto es lo que se explicó en el recuadro de la sección 1.

- **Propuesta:** en `actualizar.ps1`, justo antes de `git push origin main`, agregar `git pull --rebase origin main`.
- Si el pull falla, que avise y frene sin publicar.
- Así, lo que se mergee desde GitHub (este PR y los de las otras sesiones) llega solo a la PC.

### Impacto MEDIO

#### G2. 31 páginas de artista indexables con el nombre en MAYÚSCULAS

- **Ejemplos:** «Vinilos de MERCEDES SOSA», «OSVALDO PUGLIESE», «FRANK SINATRA», «DEEP PURPLE», «BEE GEES».
- **De dónde viene:** de los datos. Hay **345 discos** con el campo «Nombre del artista» en mayúsculas en Mercado Libre (por ejemplo «RICK WAKEMAN», «LOS FABULOSOS CADILLACS»). En 137 artistas conviven dos grafías.
  - El generador elige la grafía más repetida, y en estos casos gana la de mayúsculas.
  - El nombre también sale en mayúsculas en el título de 329 fichas.
- **Corrección de fondo:** corregir el atributo en las publicaciones de ML.
- **Mientras tanto, en el generador** (`Sync-Hubs`, donde se elige `$nombre`, y lo mismo en `Get-ArtistasConPagina`): antes de ordenar por cantidad, poner las grafías en mayúsculas al final.
  ```powershell
  Sort-Object @{Expression={ $_.Name -ceq $_.Name.ToUpper() }}, @{Expression='Count';Descending=$true}, @{Expression={$_.Name.Length}}
  ```
  Esto solo cambia la elección cuando existe otra grafía, así que no toca «ABBA» ni «AC/DC».

#### G3. 444 fichas con título idéntico a otra (204 grupos)

- **Ejemplo:** «ABBA — The Visitors · Vinilo 1981 | Respira Ventas» aparece en dos fichas (`1104506953` y `1759519304`).
  - No son publicaciones duplicadas, porque las fotos son distintas: son **varias copias del mismo disco**.
  - Hay 179 grupos de 2 copias, 18 de 3, 3 de 4 y 4 de 5.
  - Para Google son páginas casi iguales, y suele mostrar solo una.
- **Qué cambiar** (`Build-FichaHtml` / `Sync-Fichas` en `generar-fichas.ps1`): cuando hay otro disco activo con el mismo artista y álbum, agregar al `<title>` y a la meta descripción lo que los diferencia. Lo más claro es el estado, por ejemplo «· Disco VG+ / Tapa EX». También sirven el sello o el origen.

#### G4. 318 páginas generadas sin `og:image`

- **Cuáles:** 311 páginas de artista, 5 de década, `compilados.html` y `maxis.html`.
- **Efecto:** al compartirlas por WhatsApp no sale ninguna foto.
- **Qué cambiar:** en `Build-HubHtml` (`generar-hubs.ps1`), agregar un parámetro `$ogImagen` y emitir `<meta property="og:image" content="...">`.
  - Desde `Sync-Hubs`, pasarle la primera imagen del primer disco de la lista.
  - Para las páginas sin discos, pasarle `https://respiraventas.com.ar/assets/logo-icon.jpg`.

#### D1. Datos de Mercado Libre inconsistentes (corregir en las publicaciones)

| Problema | Cantidad | Ejemplos (ID de ML) | Efecto en el sitio |
|---|---|---|---|
| Género en dos grafías: «Banda de Sonido» (68) y «Banda De Sonido» (1) | 1 | MLA4120859778 | En el filtro de géneros aparecen dos opciones distintas |
| Género «ROCK ARGENTINO» en mayúsculas | 233 | — | Se ve en mayúsculas en la etiqueta, la miga de pan y el JSON-LD de 233 fichas |
| Origen escrito de varias formas: «EE. UU.» (3) y «EEUU» (1) en vez de «Estados Unidos»; «Cub» (4) en vez de «Cuba»; «Holanda» (1) y «Países Bajos» (2); «Inglaterra» (24) y «Reino Unido» (1) | 11 | — | El filtro de origen muestra opciones repetidas o truncadas |
| Año inválido «11» | 1 | MLA1937331452 (Javier Solís y el Trío Los Panchos – Juntos!) | El título dice «Vinilo 11» y el JSON-LD lleva `releaseDate: "11"`, que es inválido |
| Sin año | 1 | MLA2966424870 (Compilado Chelsea Movin Vol 4) | No entra en ninguna década |
| Campo artista con texto del título («Vinilo LP», «Sin Girar», el nombre del álbum) | 14 | MLA1317801756 «Silvestre - 100 Días de Ana - Andrea del Boca Vinilo LP», MLA1317820993, MLA1317782633, MLA1322225049, MLA1322205614, MLA1265722479 «Vinilo Manolo Galvan», MLA1239579418 | Títulos raros y una página de artista que no corresponde |
| Artista con 2 nombres separados por « - » (dúos) | ~76 | «Binelli - Romero», «Enoch Light - Tony Mottola» | No se agrupan con el artista solo (el separador « - » no está en `$SEP_COLAB`). Es aceptable. |
| Descripción sin las líneas «Disco: …» / «Tapa: …» | 532 | MLA1104989827 dice «Discos: VG» y «Tapa Gatefold: VG», que no coinciden con el patrón | La ficha no muestra el recuadro «Estado del disco (escala Goldmine)». En 467 el estado está escrito dentro del texto. |
| Descripción idéntica a la de otros discos | 700 | 196 dicen solo «Vinilo Sin Girar o NM - De disquería cerrada.» y 180 «Disco perteneciente a Lote…» | Contenido duplicado y pobre en esas fichas |

Si se prefiere no editar cientos de publicaciones, `actualizar.ps1` podría normalizar estos valores al leer el Excel con una tabla fija de equivalencias, por ejemplo `'EE. UU.'='Estados Unidos'`, `'Cub'='Cuba'`, `'Banda De Sonido'='Banda de Sonido'`. Los links viejos con `?genero=` siguen funcionando, porque `app.js` compara sin distinguir mayúsculas.

#### T1. Textos de las páginas temáticas que prometen artistas que no hay en stock

| Página | Texto | Discos en el catálogo hoy |
|---|---|---|
| `cumbia-cuarteto.html` (meta descripción) | «Gilda, Rodrigo, La Mona Jiménez…» | Gilda: 0; La Mona: 0 propios (su página quedó vacía); Rodrigo: 1 |
| `melodico.html` (meta descripción) | «Sandro…» | Ninguno a nombre de Sandro |
| `brasil.html` (meta descripción y tarjetas) | «Jobim, Caetano Veloso, Gilberto Gil» | 1, 0 propios y 1 |
| `rock-nacional.html` (meta descripción) | «Spinetta…» | 1 |
| `tango.html` (meta descripción) | «Gardel…» | 1 |
| `rock-nacional.html` | «Más de 4.100 títulos disponibles» y «4.100+ Discos disponibles» | Es el total del catálogo, pero en esta página se lee como si fuera solo rock nacional, que tiene 233 discos |

Es texto comercial, así que **no se cambió**: lo decide el dueño. Quien busca «vinilo Gilda» y llega a la página no encuentra nada y se va, y eso perjudica el posicionamiento.

### Impacto BAJO

| # | Hallazgo | Cantidad | Dónde se corrige |
|---|---|---|---|
| G5 | `releaseDate` inválido en el JSON-LD cuando el año no tiene 4 cifras. Hoy es 1 ficha (`disco/1937331452-…`). | 1 | `generar-fichas.ps1`: cambiar `if ($anio) { $ld['releaseDate'] = $anio }` por `if ($anio -match '^\d{4}$') { … }` |
| G6 | Títulos de ficha largos (Google muestra unos 60 caracteres). Hay 1.517 fichas de más de 70 caracteres y 162 de más de 100. El más largo tiene 265 caracteres (zarzuela con 9 intérpretes) y otros repiten el artista dentro del álbum. | 1.517 | `Build-FichaHtml`: si `$artista` pasa los 50 caracteres, usar solo el primer nombre (lo que va antes de `$SEP_COLAB`) en el `<title>`. También se puede sacar « \| Respira Ventas» cuando el título pasa los 65. |
| G7 | Las páginas `d/*.html` redirigen solo con JavaScript. No tienen `<link rel="canonical">` ni una redirección de respaldo para navegadores o robots sin JS. Todas apuntan bien a su ficha (verificado en las 4.250). | 4.250 | `Build-SharePageHtml`: agregar `<link rel="canonical" href="$SITE_URL$destino">` y `<meta http-equiv="refresh" content="0;url=$destino">` |
| G8 | Dos registros viejos de `vendidos.json` no tienen el campo `ficha` (MLA2019128980 y MLA3810145732). Sus fichas existen. El «Caso 2» de `Sync-Hubs` arma el link con `$_.ficha`, así que generaría `/disco/` vacío si esos artistas cayeran en ese caso (hoy no pasa). | 2 | `generar-hubs.ps1`, Caso 2: usar `$(Get-FichaNombre $_)` en vez de `$($_.ficha)` |
| G9 | Cantidades escritas a mano que el script no actualiza: «286 Discos de tango» (hoy hay 293) y «300 Discos de Folklore» (hoy hay 308). Hoy no mienten, porque se quedan cortas, pero se van a desactualizar. | 2 | Extender `Update-TotalEnLanding` (`actualizar.ps1`) con el conteo por género, redondeado hacia abajo a la decena, o reemplazar el número por un texto sin cifra |
| G11 | Una imagen se repite en 1.390 discos y otras en 352, 185 y 173 (probablemente una foto genérica de las publicaciones de ML). Va en el `image` del JSON-LD de cada producto. No se pudo ver cuál es (ver Limitaciones). | 1.390 | Si es genérica: en `Build-FichaHtml`, no pasar al JSON-LD las imágenes que aparecen en más de 20 discos (en la galería pueden quedar) |
| G12 | 17 páginas de artista sin JSON-LD. Todas tienen `noindex` (artista sin discos o «mudado»), así que no afecta. | 17 | Opcional: pasar `-ldJson` también en los dos casos de «páginas sin discos propios» |
| H1 | `index.html` no tiene `<h1>`. El texto visible que haría de título es el banner «Más de 4.100 discos de vinilo». | 1 | A mano, pero toca diseño y CSS: conviene que lo haga la sesión de celular y velocidad. Tiene que conservar el texto «Más de N discos», que el script actualiza. |
| M1 | Meta descripciones de 161 a 167 caracteres (Google corta en unos 155): `folklore.html`, `melodico.html`, `tango.html` y 5 páginas de artista «Y Su Orquesta Típica». Esas 5 se resuelven con G1. | 8 | Texto a mano (las 3 páginas temáticas) |
| R1 | El deploy publica **todo** el repositorio, incluidos `_PABLO/` y este archivo. `robots.txt` le pide a Google que no indexe `_PABLO/`, pero los archivos se pueden descargar igual. No hay contraseñas, solo el mail y el WhatsApp, que ya son públicos, y rutas de la PC. | — | Opcional: en `deploy.yml`, subir una copia sin `_PABLO/` ni `*.md` |

---

## 4. Lo que se verificó y está bien

| Chequeo | Resultado |
|---|---|
| Links internos (`<a>`, `<img>`, `<link>`, `<script>`) en las **10.017 páginas**, incluidas `404.html` y las páginas temáticas | **0 rotos** |
| Links con filtros: `?genero=` (8.512), `?artista=` (1.133), `?decada=`, `?tipo=` y `?orden=` | **Todos apuntan a valores que existen** en el catálogo |
| Redirecciones de `d/*.html` | Las 4.250 apuntan a la ficha correcta |
| Páginas indexables sin links entrantes (huérfanas) | **0** (fichas, artistas, décadas, colecciones y temáticas) |
| `sitemap.xml` (índice) | Lista los 3 sitemaps, y los 3 existen |
| `sitemap-discos.xml` | 4.172 URLs, **exactamente** los discos activos; ninguna vendida |
| `sitemap-hubs.xml` / `sitemap-paginas.xml` | 318 y 8 URLs; todas existen, son indexables y coinciden con su canónica |
| Páginas indexables que faltan en algún sitemap | **0** |
| URLs en sitemaps con `noindex` o que no coinciden con su canónica | **0** |
| `<link rel="canonical">` | Presente y correcto en todas las páginas que no son redirecciones |
| Imágenes sin `alt`, con `alt` vacío, con `src` vacío o con `http://` | **0** |
| JSON-LD inválido (no se puede leer) | **0** |
| Estado de las fichas: activas indexables y vendidas con `noindex` y la marca «Vendido» | Coherente en las 4.250 |
| `records.json`: IDs duplicados, fichas inexistentes, `artistaUrl` rotas o discos sin imágenes ni precio | **0** |
| Publicaciones duplicadas (mismo artista, mismo álbum y misma foto de portada) | **0** |
| `robots.txt` | Correcto: permite todo salvo `_PABLO/` y declara el sitemap |

## 5. Limitaciones de esta auditoría

- **No se pudo comprobar si las fotos de Mercado Libre cargan.** Son 16.646 URLs de `http2.mlstatic.com`, y la red de este entorno bloquea ese dominio y también el sitio publicado. Se revisó que todas usen `https` y que ningún disco esté sin fotos. Un chequeo de imágenes rotas habría que correrlo desde una PC con internet.
- **No se pudieron ejecutar los generadores de PowerShell** en este entorno. Por eso **ningún `.ps1` se modificó**: un error en `generar-fichas.ps1` frenaría la actualización completa del catálogo (se carga fuera del `try/catch`). Los cambios G1 a G12 están escritos para aplicarlos y probarlos en la PC de Pablo con una actualización normal.
- Los números corresponden al catálogo del 01/11/2026 (4.172 activos y 78 vendidos).

## 6. Orden sugerido para lo que queda

1. **G10** (`git pull` antes del push), para que lo mergeado en GitHub llegue a la PC.
2. **G1** (agrupar «Y Su Orquesta»): es una línea y es la mejora de SEO más grande.
3. **G2 y D1**: corregir las mayúsculas y las grafías en Mercado Libre, o con la tabla de normalización.
4. **G4 y G3**: `og:image` en las páginas de artista y títulos distintos para las copias repetidas.
5. **T1**: revisar los textos de las páginas temáticas.
6. El resto de la tabla de impacto bajo.
