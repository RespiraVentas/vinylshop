# Tests automáticos del sitio

Son pruebas que GitHub corre solo, cada vez que alguien propone un cambio
(un *pull request*). La idea es detectar un error **antes** de que llegue a la
web: un link roto, un filtro que deja de andar, un precio que no coincide, un
sitemap que apunta a una página que no existe.

**Resumen:** son dos partes.

| Parte | Qué revisa | Tarda |
|---|---|---|
| **Verificador del sitio** | Los archivos del repositorio: links, imágenes, datos, JSON-LD y sitemaps de las ~10.000 páginas | ~5 segundos |
| **Tests de navegador** | Abre el sitio en un Chrome de verdad, en **escritorio** y en **celular**, y lo usa como una persona: busca, filtra, abre discos, navega | ~1–2 minutos |

---

## Dónde está todo (y por qué ahí)

Todo lo de tests vive dentro de la carpeta `.github/`:

```
.github/
├── TESTS.md                  ← este archivo
├── workflows/
│   ├── deploy.yml            ← el que publica el sitio (no se tocó)
│   └── tests.yml             ← el nuevo: corre los tests en cada pull request
└── tests/
    ├── verificar-sitio.js    ← el verificador del sitio
    ├── fallas-conocidas.json ← errores reales ya conocidos (ver más abajo)
    ├── servidor.js           ← sirve el sitio en tu compu para probarlo
    ├── playwright.config.js  ← configuración de los tests de navegador
    ├── package.json          ← la única herramienta que se instala: Playwright
    └── navegador/            ← los tests de navegador
        ├── catalogo.spec.js
        ├── filtros-compartidos.spec.js
        ├── navegacion.spec.js
        └── ayuda.js
```

**¿Por qué en `.github/`?** Porque el paso que publica el sitio
(`deploy.yml` → `upload-pages-artifact`) sube todo el repositorio **menos**
`.git` y `.github`. Así, nada de esto se publica en respiraventas.com.ar, no
suma peso al sitio y no hace falta tocar el flujo de publicación. Este archivo
también está ahí a propósito: lista errores del sitio y no tiene por qué estar
a la vista del público.

---

## Qué revisa el verificador del sitio

Lee los archivos sin abrir un navegador y sin internet. Cada error que encuentra
pertenece a una "regla":

**Datos (`data/records.json` y `data/vendidos.json`)**
- Que los JSON se puedan leer.
- Que cada disco tenga título, link de Mercado Libre, precio (los que están en venta) y fotos.
- Que no haya discos repetidos, ni un disco a la vez en venta y vendido.
- Que la ficha de cada disco (`/disco/...`) exista, también la de los vendidos (para que no se rompan los links que la gente ya compartió).
- Que el link al artista lleve a una página que existe.
- Que el año sea un año (por ejemplo, no "11").
- Que un mismo género no esté escrito de dos formas ("Banda de Sonido" y "Banda De Sonido" aparecen como dos opciones distintas en el filtro).

**Links e imágenes de todas las páginas**
- Todo link interno (`href`, `src`, `og:image`, canonical, las redirecciones de `/d/...`) tiene que llevar a un archivo que existe.
- Las imágenes locales (logo, íconos) tienen que existir y ningún `<img>` puede quedar sin dirección.
- Los links que abren el catálogo filtrado (`/?genero=Tango`, `/?tipo=Compilados`, `/?decada=1970`, `/?artista=...`) tienen que usar valores que el catálogo realmente tiene. Si no, el visitante ve el catálogo entero en vez del filtrado, sin ningún aviso.
- Cada página tiene `<title>` y su "canonical" apunta a ella misma.

**Datos para Google (JSON-LD)**
- Cada bloque es JSON válido y tiene lo que Google pide (nombre, foto, precio, moneda, disponibilidad, miga de pan bien numerada).
- El precio de cada ficha es **el mismo** que calcula el catálogo (`precioSitio()` de `app.js`). Hoy ese cálculo está repetido en `app.js` y en `generar-fichas.ps1`; si alguna vez dejan de coincidir, esto lo detecta.
- Los discos en venta dicen "InStock" y los vendidos "SoldOut".

**Sitemaps**
- `robots.txt` apunta a `sitemap.xml`, y este a sitemaps que existen.
- Cada página listada existe, usa el dominio del `CNAME`, no está repetida y no está marcada para no indexar.
- Ninguna página indexable queda afuera de todos los sitemaps.

> No revisa las fotos de Mercado Libre una por una (están en otro servidor y
> haría falta internet); sí revisa que cada disco tenga fotos cargadas.

## Qué revisan los tests de navegador

Cada test corre **dos veces**: en una pantalla de escritorio (1366×800) y en un
celular (Pixel 7). En total son 120. Bloquean todo lo externo (fuentes de
Google, fotos de Mercado Libre) para no depender de internet, y cualquier error
de JavaScript en la página hace fallar el test.

**Catálogo (`catalogo.spec.js`)**
- Carga todos los discos de `records.json`; muestra 60 y "Cargar más" agrega otros 60.
- Cada tarjeta tiene artista, álbum, precio, link a su ficha y botón de WhatsApp.
- Búsqueda: encuentra la cantidad correcta, no le importan tildes, mayúsculas ni el orden de las palabras, avisa cuando no hay resultados.
- Filtros de género, origen, década, tipo y orden: filtran bien, se combinan, y "Limpiar" deja todo como al principio.

**Filtros compartidos por dirección (`filtros-compartidos.spec.js`)**
- Abrir `/?q=...`, `/?genero=...`, `/?decada=...&tipo=...&orden=...`, `/?artista=...` o `/?id=...` muestra el catálogo tal como se compartió.
- Filtrar, copiar la dirección y abrirla en otra pestaña da exactamente el mismo resultado.
- Valores inexistentes o caracteres raros no rompen la página.
- Cada botón de las páginas de colección y de década que abre el catálogo filtrado (por ejemplo "Ver todos los discos de Rock Nacional") muestra discos y no el catálogo vacío ni entero.

**Navegación (`navegacion.spec.js`)**
- Catálogo → ventana del disco → discos relacionados → página del artista.
- Ficha del disco: título, precio igual al del catálogo, WhatsApp con el link de la ficha, miga de pan, relacionados, link al artista y vuelta al catálogo.
- Página de artista: lista todos sus discos y cada uno abre su ficha.
- Los links para compartir (`/d/...`) redirigen a la ficha.
- Discos vendidos: la ficha sigue existiendo, avisa "Vendido" y no aparece en el catálogo.
- Colecciones → década → catálogo filtrado; el contador de Melódico se actualiza.
- Una dirección que no existe muestra la página de error con salida al catálogo.
- En celular y escritorio: nada se sale de la pantalla hacia los costados, los filtros entran en la pantalla, y la ventana del disco se ve completa y se puede cerrar.

Los discos que usan los tests se eligen del catálogo del momento (no con
números fijos), así los tests siguen andando aunque se vendan discos o entren
nuevos.

---

## Cuándo corren

- **En cada pull request contra `main`.** En la página del pull request aparece
  "Tests del sitio" con un ✓ verde o una ✗ roja. Tocando "Details" se ve qué falló.
- **A mano**, desde la pestaña *Actions* → *Tests del sitio* → *Run workflow*.

**No corren** en la actualización automática del catálogo: `actualizar.ps1`
sube directo a `main`, y este flujo solo mira pull requests. No la frena, no la
demora y no publica ni escribe nada en el repositorio (solo tiene permiso de
lectura).

> ⚠️ Importante: **no** activar en GitHub la protección de `main` con
> "Require status checks to pass". Eso obligaría a que todo pase por un pull
> request y **bloquearía** la subida automática del catálogo.

Si un test de navegador falla, en la corrida queda para bajar un
"informe-navegador" con capturas de pantalla de lo que se veía en ese momento.

---

## Cómo correrlo en tu compu

Hace falta tener instalado [Node.js](https://nodejs.org) (versión 22 o más nueva).
Desde la carpeta del sitio:

```bash
cd .github/tests
```

La primera vez, instalar Playwright y su navegador:

```bash
npm install
```

```bash
npx playwright install chromium
```

Correr todo (primero el verificador, después el navegador):

```bash
npm test
```

O cada parte por separado:

```bash
npm run verificar
```

```bash
npm run navegador
```

Para ver los tests de navegador en una ventana, paso a paso:

```bash
npx playwright test --ui
```

Para mirar el sitio en tu compu como si estuviera publicado
(queda en http://127.0.0.1:4173):

```bash
npm run servidor
```

El verificador muestra hasta 15 ejemplos por regla. Para ver todos:

```bash
node verificar-sitio.js --todos
```

Estos comandos andan igual en Windows (PowerShell), Mac y Linux.

---

## Errores reales que aparecieron

Se corrieron los tests sobre el sitio tal como está hoy en `main`
(actualización del 01/11/2026, 4.172 discos en venta y 78 vendidos).

**Los tests de navegador pasaron todos** (120 de 120, en escritorio y celular).
El verificador no encontró links rotos, imágenes locales faltantes, JSON-LD
inválido, precios distintos entre ficha y catálogo, ni problemas en los
sitemaps.

Encontró **2 errores reales, los dos en los datos del catálogo**. Acá no se
arreglaron (esta tarea solo agrega tests). Quedaron anotados como **fallas
conocidas**, así el flujo no queda en rojo por ellos:

| # | Regla | Qué pasa | Cómo se arregla |
|---|---|---|---|
| 1 | `datos-anio` | *Javier Solís y el Trío Los Panchos – Juntos!* (MLA1937331452) tiene año **"11"**. No aparece en ningún filtro de década, y la ficha muestra "11" como año (también en los datos para Google). | Corregir el año de esa publicación en el Excel y actualizar el catálogo. |
| 2 | `datos-genero-repetido` | Hay 68 discos con género **"Banda de Sonido"** y 1 con **"Banda De Sonido"** (*Dimitri Papadopoulos – Grandes éxitos del cine*, MLA4120859778). El filtro de géneros muestra las dos opciones, y elegir una no muestra los discos de la otra. | Escribir el género igual que los demás en el Excel y actualizar el catálogo. |

Otras cosas que se vieron y **no** se cuentan como error, porque el sitio
funciona bien igual:

- Dos discos de `vendidos.json` (MLA2019128980 y MLA3810145732) no traen los
  campos `ficha` ni `artistaUrl`. Sus fichas de "vendido" existen igual; el
  verificador las encuentra por el número.
- `records.json` y `vendidos.json` empiezan con una marca invisible (BOM). Los
  navegadores la ignoran sin problema; los tests también.
- `melodico.html` tiene escrito "771 discos" pero el catálogo tiene 790. No es
  un error: la página corrige el número sola al cargar (hay un test que lo
  comprueba).

---

## Fallas conocidas: cómo funcionan

Están en `.github/tests/fallas-conocidas.json`. Mientras un error figure ahí:

- se muestra en el informe como aviso (en amarillo), y
- **no** hace fallar el flujo.

Cuando un error se arregla, el informe avisa *"ya no aparece, se puede sacar de
fallas-conocidas.json"*. Conviene sacarlo para que, si vuelve, se note.

- **En el verificador**, cada entrada tiene la `regla`, un `patron` (texto que
  tiene que aparecer en el error, por ejemplo el número del disco) y el `motivo`.
  Así, si aparece **otro** disco con el mismo problema, sí se avisa.
- **En el navegador**, cada entrada tiene el título exacto del `test` y el
  `motivo`. Ese test queda como "salteado: falla conocida" en vez de rojo.

Ejemplo (la primera entrada es real; la de navegador es solo el formato):

```json
{
  "verificador": [
    { "regla": "datos-anio", "patron": "1937331452", "motivo": "Año \"11\" en el Excel" }
  ],
  "navegador": [
    { "test": "título exacto del test", "motivo": "qué pasa y dónde se va a arreglar" }
  ]
}
```

---

## Si un test falla en un pull request

1. Abrir "Details" en el pull request y leer el mensaje: dice qué regla o qué
   test falló, en qué página y qué se esperaba.
2. Si es un error del cambio propuesto → corregirlo en el mismo pull request.
3. Si es un error que ya estaba en `main` (por ejemplo, entró con una
   actualización del catálogo) → anotarlo en `fallas-conocidas.json` con su
   motivo y arreglarlo aparte.
4. Si el test quedó viejo porque el sitio cambió a propósito (por ejemplo, se
   cambió cuántos discos muestra por tanda) → actualizar el test.

## Mantenimiento

- **Una sola herramienta instalada:** Playwright (versión fija en
  `package.json`). El verificador y el servidor no usan ninguna librería.
- **Página o colección nueva:** el verificador la revisa sola (links, título,
  sitemap). Si tiene un botón que abre el catálogo filtrado, también se prueba
  solo en el navegador.
- **Filtro nuevo en el catálogo:** agregarlo a la lista `FILTROS` de
  `verificar-sitio.js` para que se validen los links que lo usan, y sumar un test
  en `catalogo.spec.js`.
- **Actualizar Playwright:** cambiar la versión en `package.json`, correr
  `npm install` en `.github/tests` y subir también `package-lock.json`.
