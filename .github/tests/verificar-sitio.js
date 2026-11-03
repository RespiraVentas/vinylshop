#!/usr/bin/env node
// Verificador del sitio estático.
//
// Lee los archivos del repositorio (sin navegador y sin internet) y revisa:
//   1. Que los JSON de data/ sean válidos y que cada disco tenga lo necesario.
//   2. Que los links internos de todas las páginas lleven a algo que existe.
//   3. Que no falten imágenes locales y que cada disco tenga fotos.
//   4. Que los links que abren el catálogo filtrado (/?genero=..., /?tipo=...)
//      usen valores que el catálogo realmente tiene.
//   5. Que los datos estructurados para Google (JSON-LD) sean válidos.
//   6. Que los sitemaps solo apunten a páginas que existen y se pueden indexar.
//
// Uso:   node verificar-sitio.js           (--todos: muestra todos los casos, no solo 15 por regla)
// Sale con código 1 si encuentra errores nuevos. Los errores que ya se conocen
// (anotados en fallas-conocidas.json) se muestran, pero no hacen fallar.

'use strict';
const fs = require('fs');
const path = require('path');

// RAIZ_SITIO permite revisar otra copia del sitio (se usa para probar el propio verificador).
const RAIZ = path.resolve(process.env.RAIZ_SITIO || path.join(__dirname, '..', '..'));
const CONOCIDAS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fallas-conocidas.json'), 'utf8'));

// ── Reglas: cada error que se informa pertenece a una de estas ───────────────
const REGLAS = {
  'json-invalido':             'Archivo JSON de data/ que no se puede leer',
  'datos-campo':               'Disco con un dato obligatorio vacío o mal escrito',
  'datos-duplicado':           'Disco repetido en los datos',
  'datos-ficha-inexistente':   'Disco cuya ficha (/disco/...) no existe',
  'datos-artista-inexistente': 'Disco cuyo link de artista lleva a una página que no existe',
  'datos-anio':                'Disco con un año que no parece un año',
  'datos-genero-repetido':     'El mismo género escrito de dos formas (aparece dos veces en el filtro)',
  'link-roto':                 'Link interno a una página o archivo que no existe',
  'imagen-faltante':           'Imagen local que no existe, o imagen sin dirección',
  'filtro-invalido':           'Link al catálogo con un filtro que el catálogo no reconoce',
  'html-sin-titulo':           'Página sin <title>',
  'canonical-incorrecto':      'La dirección "canonical" no es la de la propia página',
  'jsonld-invalido':           'Bloque JSON-LD que no es JSON válido',
  'jsonld-incompleto':         'Bloque JSON-LD al que le falta un dato que Google pide',
  'precio-distinto':           'La ficha muestra un precio distinto al que calcula el catálogo',
  'disponibilidad-incorrecta': 'Ficha marcada "en stock" estando vendida, o al revés',
  'sitemap-roto':              'Sitemap que no existe o está mal armado',
  'sitemap-pagina-inexistente':'El sitemap apunta a una página que no existe',
  'sitemap-noindex':           'El sitemap apunta a una página marcada para no indexar',
  'sitemap-duplicado':         'La misma página aparece dos veces en los sitemaps',
  'sitemap-dominio':           'El sitemap usa un dominio distinto al del sitio (CNAME)',
  'sitemap-falta-pagina':      'Página indexable que no figura en ningún sitemap',
};

const problemas = [];   // { regla, archivo, detalle }
const yaReportado = new Set();
function reportar(regla, archivo, detalle) {
  if (!REGLAS[regla]) throw new Error(`Regla desconocida: ${regla}`);
  const clave = `${regla}|${archivo}|${detalle}`;
  if (yaReportado.has(clave)) return;   // el mismo link dos veces en una página cuenta una sola vez
  yaReportado.add(clave);
  problemas.push({ regla, archivo, detalle });
}

// ── Utilidades ────────────────────────────────────────────────────────────────
const leer = rel => fs.readFileSync(path.join(RAIZ, rel), 'utf8').replace(/^\uFEFF/, '');
const posix = p => p.split(path.sep).join('/');

function listarArchivos(dir = RAIZ, salida = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    // Nada que empiece con punto (.git, .github): GitHub Pages no los publica.
    if (e.name.startsWith('.') || e.name === 'node_modules') continue;
    const abs = path.join(dir, e.name);
    if (e.isDirectory()) listarArchivos(abs, salida);
    else salida.push(posix(path.relative(RAIZ, abs)));
  }
  return salida;
}

const ARCHIVOS = new Set(listarArchivos());
const HTMLS = [...ARCHIVOS].filter(f => f.endsWith('.html')).sort();
const DOMINIO = ARCHIVOS.has('CNAME') ? leer('CNAME').trim() : '';
const ORIGEN = `https://${DOMINIO || 'sitio.local'}`;

// Igual que GitHub Pages: "/x" sirve x, x/index.html o x.html.
function archivoDe(pathname) {
  let rel;
  try { rel = decodeURIComponent(pathname); } catch { rel = pathname; }
  rel = rel.replace(/^\/+/, '');
  if (rel === '' ) return ARCHIVOS.has('index.html') ? 'index.html' : null;
  rel = rel.replace(/\/+$/, '');
  for (const c of [rel, `${rel}/index.html`, `${rel}.html`]) if (ARCHIVOS.has(c)) return c;
  return null;
}

// Convierte un href/src en una URL absoluta si es del propio sitio, o null si
// es externa o no es un link (mailto:, data:, #ancla...).
function urlInterna(valor, archivoBase) {
  const v = (valor || '').trim();
  if (!v || v.startsWith('#')) return null;
  if (/^(mailto|tel|javascript|data|blob|whatsapp):/i.test(v)) return null;
  let u;
  try { u = new URL(v, `${ORIGEN}/${archivoBase}`); } catch { return null; }
  if (!/^https?:$/.test(u.protocol)) return null;
  const host = u.hostname.replace(/^www\./, '');
  if (host !== new URL(ORIGEN).hostname) return null;
  return u;
}

const decodificarEntidades = s => s
  .replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;|&#x27;/g, "'")
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>');

// ── 1. Datos (data/*.json) ────────────────────────────────────────────────────
function leerJSON(rel) {
  try { return JSON.parse(leer(rel)); }
  catch (e) { reportar('json-invalido', rel, e.message); return null; }
}

for (const f of [...ARCHIVOS].filter(f => /^data\/.*\.json$/.test(f))) leerJSON(f);

const records  = leerJSON('data/records.json')  || [];
const vendidos = ARCHIVOS.has('data/vendidos.json') ? (leerJSON('data/vendidos.json') || []) : [];
if (!Array.isArray(records))  reportar('json-invalido', 'data/records.json', 'no es una lista de discos');
if (!Array.isArray(vendidos)) reportar('json-invalido', 'data/vendidos.json', 'no es una lista de discos');

const idDe = r => ((r && r.url) || '').match(/MLA-?(\d+)/)?.[1] || '';
// Archivo de la ficha de un disco. En vendidos.json algunos discos no traen el
// campo "ficha" (el sitio no lo usa); ahí se busca la página por el número.
const FICHAS_POR_ID = new Map([...ARCHIVOS]
  .filter(f => /^disco\/\d+-/.test(f))
  .map(f => [f.match(/^disco\/(\d+)-/)[1], f.slice('disco/'.length)]));
const fichaDe = r => (r && typeof r.ficha === 'string' && r.ficha) || FICHAS_POR_ID.get(idDe(r)) || '';
const ANIO_ACTUAL = new Date().getFullYear();

function revisarDisco(r, archivo, enVenta) {
  const nombre = `${idDe(r) || '(sin id)'} ${r.titulo || ''}`.trim();
  const falta = campo => reportar('datos-campo', archivo, `${nombre}: ${campo}`);
  if (!r || typeof r !== 'object') return falta('no es un objeto');
  if (typeof r.titulo !== 'string' || !r.titulo.trim()) falta('sin título');
  if (!idDe(r)) falta(`url de Mercado Libre inválida (${r.url})`);
  if (enVenta && !(typeof r.precio === 'number' && r.precio > 0)) falta(`precio inválido (${r.precio})`);
  if (!Array.isArray(r.imagenes) || r.imagenes.length === 0) {
    reportar('imagen-faltante', archivo, `${nombre}: el disco no tiene fotos`);
  } else if (r.imagenes.some(i => typeof i !== 'string' || !/^https:\/\//.test(i))) {
    reportar('imagen-faltante', archivo, `${nombre}: foto con dirección inválida`);
  }
  if (r.tipos !== undefined && !Array.isArray(r.tipos)) falta('"tipos" no es una lista');
  if (r.fecha && isNaN(Date.parse(r.fecha))) falta(`fecha inválida (${r.fecha})`);
  if (r.anio && !(/^\d{4}$/.test(r.anio) && +r.anio >= 1900 && +r.anio <= ANIO_ACTUAL)) {
    reportar('datos-anio', archivo, `${nombre}: año "${r.anio}"`);
  }
  const ficha = fichaDe(r);
  if (!ficha) {
    // Un vendido sin ficha propia rompería los links viejos que la gente compartió.
    if (enVenta || !idDe(r)) falta('sin ficha');
    else reportar('datos-ficha-inexistente', archivo, `${nombre}: no hay ninguna disco/${idDe(r)}-....html`);
  } else if (!ARCHIVOS.has(`disco/${ficha}`)) {
    reportar('datos-ficha-inexistente', archivo, `${nombre}: disco/${ficha}`);
  }
}

const slugsArtista = new Set(records.map(r => r && r.artistaSlug).filter(Boolean));
const vistos = new Map();
for (const [lista, archivo, enVenta] of [[records, 'data/records.json', true], [vendidos, 'data/vendidos.json', false]]) {
  if (!Array.isArray(lista)) continue;
  for (const r of lista) {
    revisarDisco(r, archivo, enVenta);
    const id = idDe(r);
    if (id) {
      if (vistos.has(id)) reportar('datos-duplicado', archivo, `${id} ${r.titulo || ''} (también en ${vistos.get(id)})`);
      else vistos.set(id, archivo);
    }
    // El link de artista que usa el catálogo (app.js) al abrir un disco
    if (enVenta && r.artistaUrl) {
      const u = urlInterna(r.artistaUrl, 'index.html');
      if (u && u.pathname !== '/' && !archivoDe(u.pathname)) {
        reportar('datos-artista-inexistente', archivo, `${idDe(r)} ${r.titulo}: ${r.artistaUrl}`);
      }
      const slug = u && u.searchParams.get('artista');
      if (slug && !slugsArtista.has(slug)) {
        reportar('datos-artista-inexistente', archivo, `${idDe(r)} ${r.titulo}: ${r.artistaUrl}`);
      }
    }
  }
}

// Géneros que solo difieren en mayúsculas: el desplegable los muestra dos veces
// y el link /?genero=... solo puede elegir uno de los dos.
const generos = [...new Set(records.map(r => r && r.genero).filter(Boolean))];
const porMinuscula = new Map();
for (const g of generos) {
  const k = g.toLowerCase();
  porMinuscula.set(k, [...(porMinuscula.get(k) || []), g]);
}
for (const variantes of porMinuscula.values()) {
  if (variantes.length > 1) reportar('datos-genero-repetido', 'data/records.json', variantes.map(v => `"${v}"`).join(' y '));
}

// ── 2-4. Páginas HTML: links, imágenes, filtros, títulos ──────────────────────
// Valores que acepta cada filtro del catálogo, igual que los arma app.js.
const indexHtml = ARCHIVOS.has('index.html') ? leer('index.html') : '';
const opcionesDe = id => {
  const m = indexHtml.match(new RegExp(`<select[^>]*id="${id}"[^>]*>([\\s\\S]*?)</select>`));
  return m ? [...m[1].matchAll(/value="([^"]*)"/g)].map(x => x[1]).filter(Boolean) : [];
};
const FILTROS = {
  genero: { valores: generos, mayus: false },
  origen: { valores: [...new Set(records.map(r => r && r.origen).filter(Boolean))], mayus: false },
  tipo:   { valores: [...new Set(records.flatMap(r => (r && r.tipos) || []))], mayus: false },
  decada: { valores: opcionesDe('filter-decade'), mayus: true },
  orden:  { valores: opcionesDe('filter-sort'), mayus: true },
  artista:{ valores: [...slugsArtista], mayus: true },
};
const idsCatalogo = new Set(records.map(idDe).filter(Boolean));

function revisarFiltros(u, archivo, regla = 'filtro-invalido') {
  for (const [clave, valor] of u.searchParams) {
    const f = FILTROS[clave];
    if (f) {
      const ok = f.mayus ? f.valores.includes(valor)
                         : f.valores.some(v => v.toLowerCase() === valor.toLowerCase());
      if (!ok) reportar(regla, archivo, `${clave}=${valor} (link: ${u.pathname}${u.search})`);
    }
    if (clave === 'id' && !idsCatalogo.has(valor.replace(/\D/g, ''))) {
      reportar(regla, archivo, `id=${valor} no está en el catálogo (link: ${u.pathname}${u.search})`);
    }
  }
}

// Revisa un destino interno. tipo: 'link' o 'imagen'.
function revisarDestino(valor, archivo, tipo) {
  const u = urlInterna(decodificarEntidades(valor), archivo);
  if (!u) return;
  const destino = archivoDe(u.pathname);
  if (!destino) {
    reportar(tipo === 'imagen' ? 'imagen-faltante' : 'link-roto', archivo, u.pathname);
    return;
  }
  if (destino === 'index.html' && u.search) revisarFiltros(u, archivo);
}

const TAG = /<(a|link|img|script|source|iframe|area|meta)\b([^>]*)>/gi;
const ATRIB = /([a-zA-Z:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
const atributos = s => Object.fromEntries([...s.matchAll(ATRIB)].map(m => [m[1].toLowerCase(), m[2] ?? m[3]]));

function revisarCssUrls(css, archivo) {
  for (const m of css.matchAll(/url\(\s*(['"]?)([^'")]+)\1\s*\)/g)) revisarDestino(m[2], archivo, 'imagen');
}

const infoPagina = new Map();   // archivo → { noindex, canonical }
const jsonldPorArchivo = new Map();

for (const archivo of HTMLS) {
  const html = leer(archivo);
  // Los bloques <script> con código se revisan aparte: su contenido no es HTML.
  const sinScripts = html.replace(/(<script\b[^>]*>)[\s\S]*?<\/script>/gi, '$1</script>');

  let noindex = false, canonical = null;
  for (const m of sinScripts.matchAll(TAG)) {
    const tag = m[1].toLowerCase();
    const a = atributos(m[2]);
    if (tag === 'meta') {
      if ((a.name || '').toLowerCase() === 'robots' && /noindex/i.test(a.content || '')) noindex = true;
      if (a.property === 'og:image' || a.property === 'og:url') revisarDestino(a.content, archivo, a.property === 'og:image' ? 'imagen' : 'link');
      continue;
    }
    if (tag === 'img') {
      if (!a.src || !a.src.trim()) reportar('imagen-faltante', archivo, '<img> sin src');
      else revisarDestino(a.src, archivo, 'imagen');
      if (a.srcset) for (const parte of a.srcset.split(',')) revisarDestino(parte.trim().split(/\s+/)[0], archivo, 'imagen');
      continue;
    }
    if (tag === 'link') {
      const rel = (a.rel || '').toLowerCase();
      if (rel === 'canonical') canonical = a.href;
      revisarDestino(a.href, archivo, /icon/.test(rel) ? 'imagen' : 'link');
      continue;
    }
    if (a.href !== undefined) revisarDestino(a.href, archivo, 'link');
    if (a.src !== undefined) revisarDestino(a.src, archivo, tag === 'script' || tag === 'iframe' ? 'link' : 'imagen');
  }

  // Estilos en línea y bloques <style>
  for (const m of sinScripts.matchAll(/style\s*=\s*"([^"]*)"/gi)) revisarCssUrls(decodificarEntidades(m[1]), archivo);
  for (const m of html.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/gi)) revisarCssUrls(m[1], archivo);

  // Scripts en línea: redirecciones (las páginas /d/...) y fetch(...)
  const bloques = [];
  for (const m of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
    const a = atributos(m[1]);
    if ((a.type || '').toLowerCase() === 'application/ld+json') { bloques.push(m[2]); continue; }
    for (const r of m[2].matchAll(/location\.(?:replace|assign)\(\s*['"]([^'"]+)['"]/g)) revisarDestino(r[1], archivo, 'link');
    for (const r of m[2].matchAll(/fetch\(\s*['"]([^'"]+)['"]/g)) revisarDestino(r[1], archivo, 'link');
  }
  jsonldPorArchivo.set(archivo, bloques);

  const titulo = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (!titulo || !titulo[1].trim()) reportar('html-sin-titulo', archivo, 'sin <title>');

  if (canonical) {
    const u = urlInterna(decodificarEntidades(canonical), archivo);
    const propio = archivoDe(u ? u.pathname : '');
    if (!u || propio !== archivo) reportar('canonical-incorrecto', archivo, canonical);
  }
  infoPagina.set(archivo, { noindex, canonical });
}

// Hojas de estilo y app.js
for (const f of [...ARCHIVOS].filter(f => f.endsWith('.css'))) revisarCssUrls(leer(f), f);
if (ARCHIVOS.has('app.js')) {
  for (const r of leer('app.js').matchAll(/fetch\(\s*['"]([^'"]+)['"]/g)) revisarDestino(r[1], 'app.js', 'link');
}

// ── 5. JSON-LD ────────────────────────────────────────────────────────────────
// Toma precioSitio() y FACTOR_PRECIO directamente de app.js, para comparar el
// precio de cada ficha con el que muestra el catálogo sin copiar la fórmula.
let precioSitio = null;
try {
  const app = leer('app.js');
  const factor = app.match(/const FACTOR_PRECIO\s*=\s*[^;]+;/)[0];
  const fn = app.match(/function precioSitio\(r\) \{[\s\S]*?\n\}/)[0];
  precioSitio = new Function(`${factor}\n${fn}\nreturn precioSitio;`)();
} catch {
  console.warn('Aviso: no se pudo leer precioSitio() de app.js; se saltea la comparación de precios.');
}

const vacio = v => v === undefined || v === null || v === '' || (Array.isArray(v) && v.length === 0);

function revisarUrlsJsonld(obj, archivo) {
  if (typeof obj === 'string') {
    const u = /^https?:\/\//.test(obj) ? urlInterna(obj, archivo) : null;
    if (u) {
      if (!archivoDe(u.pathname)) reportar('link-roto', archivo, `${u.pathname} (en JSON-LD)`);
      else if (archivoDe(u.pathname) === 'index.html' && u.search) revisarFiltros(u, archivo);
    }
  } else if (obj && typeof obj === 'object') {
    for (const v of Object.values(obj)) revisarUrlsJsonld(v, archivo);
  }
}

function revisarJsonld(d, archivo) {
  const falta = q => reportar('jsonld-incompleto', archivo, `${d['@type'] || '(sin @type)'}: ${q}`);
  if (!/schema\.org/.test(String(d['@context'] || ''))) falta('@context no es schema.org');
  if (vacio(d['@type'])) falta('@type vacío');
  switch (d['@type']) {
    case 'Product': {
      if (vacio(d.name)) falta('name vacío');
      if (vacio(d.image)) falta('image vacío');
      const o = d.offers;
      if (!o || typeof o !== 'object') { falta('sin offers'); break; }
      const precio = Number(o.price);
      if (!(precio > 0)) falta(`offers.price inválido (${o.price})`);
      if (!/^[A-Z]{3}$/.test(o.priceCurrency || '')) falta('offers.priceCurrency inválido');
      if (!/^https?:\/\/schema\.org\//.test(o.availability || '')) falta('offers.availability inválido');
      break;
    }
    case 'BreadcrumbList': {
      const items = d.itemListElement;
      if (!Array.isArray(items) || !items.length) { falta('itemListElement vacío'); break; }
      items.forEach((it, i) => {
        if (it.position !== i + 1) falta(`posición ${i + 1} mal numerada (${it.position})`);
        if (vacio(it.name)) falta(`posición ${i + 1} sin name`);
        if (i < items.length - 1 && vacio(it.item)) falta(`posición ${i + 1} sin item`);
      });
      break;
    }
    case 'CollectionPage':
    case 'WebSite':
    case 'Organization':
      if (vacio(d.name)) falta('name vacío');
      break;
  }
  revisarUrlsJsonld(d, archivo);
}

const productoPorFicha = new Map();
for (const [archivo, bloques] of jsonldPorArchivo) {
  for (const texto of bloques) {
    let d;
    try { d = JSON.parse(texto); }
    catch (e) { reportar('jsonld-invalido', archivo, e.message); continue; }
    for (const item of Array.isArray(d) ? d : (d['@graph'] || [d])) {
      revisarJsonld(item, archivo);
      if (item['@type'] === 'Product') productoPorFicha.set(archivo, item);
    }
  }
}

// Precio y disponibilidad de cada ficha contra los datos del catálogo
for (const [lista, enVenta] of [[records, true], [vendidos, false]]) {
  if (!Array.isArray(lista)) continue;
  for (const r of lista) {
    if (!fichaDe(r)) continue;
    const archivo = `disco/${fichaDe(r)}`;
    const p = productoPorFicha.get(archivo);
    if (!ARCHIVOS.has(archivo)) continue;
    if (!p) { reportar('jsonld-incompleto', archivo, 'la ficha no tiene bloque Product'); continue; }
    const disp = (p.offers && p.offers.availability) || '';
    const enStock = /InStock$/.test(disp);
    if (enVenta && !enStock) reportar('disponibilidad-incorrecta', archivo, `está en records.json pero dice ${disp}`);
    if (!enVenta && enStock) reportar('disponibilidad-incorrecta', archivo, `está en vendidos.json pero dice ${disp}`);
    if (enVenta && precioSitio && p.offers) {
      const esperado = precioSitio(r);
      if (Number(p.offers.price) !== esperado) {
        reportar('precio-distinto', archivo, `ficha ${p.offers.price}, catálogo ${esperado}`);
      }
    }
  }
}

// ── 6. Sitemaps ───────────────────────────────────────────────────────────────
const enSitemap = new Map();   // archivo → sitemap donde aparece
function leerSitemap(rel, visitados = new Set()) {
  if (visitados.has(rel)) return;
  visitados.add(rel);
  if (!ARCHIVOS.has(rel)) { reportar('sitemap-roto', rel, 'el archivo no existe'); return; }
  const xml = leer(rel).trim();
  if (!/^<\?xml[^>]*\?>/.test(xml) || !/<\/(urlset|sitemapindex)>\s*$/.test(xml)) {
    reportar('sitemap-roto', rel, 'no empieza con <?xml ...?> o no cierra <urlset>/<sitemapindex>');
  }
  const abiertas = (xml.match(/<url>/g) || []).length + (xml.match(/<sitemap>/g) || []).length;
  const locs = [...xml.matchAll(/<loc>\s*([^<]*?)\s*<\/loc>/g)].map(m => decodificarEntidades(m[1]));
  if (abiertas !== locs.length) reportar('sitemap-roto', rel, `${abiertas} entradas pero ${locs.length} <loc>`);
  const esIndice = /<sitemapindex/.test(xml);

  for (const loc of locs) {
    let u;
    try { u = new URL(loc); } catch { reportar('sitemap-roto', rel, `dirección inválida: ${loc}`); continue; }
    if (DOMINIO && (u.protocol !== 'https:' || u.hostname !== DOMINIO)) {
      reportar('sitemap-dominio', rel, loc);
      continue;
    }
    const destino = archivoDe(u.pathname);
    if (esIndice) {
      if (!destino) reportar('sitemap-roto', rel, `sitemap hijo inexistente: ${loc}`);
      else leerSitemap(destino, visitados);
      continue;
    }
    if (!destino) { reportar('sitemap-pagina-inexistente', rel, loc); continue; }
    if (enSitemap.has(destino)) reportar('sitemap-duplicado', rel, `${loc} (también en ${enSitemap.get(destino)})`);
    else enSitemap.set(destino, rel);
    const info = infoPagina.get(destino);
    if (info && info.noindex) reportar('sitemap-noindex', rel, loc);
  }
}

const robots = ARCHIVOS.has('robots.txt') ? leer('robots.txt') : '';
const sitemapsRobots = [...robots.matchAll(/^\s*Sitemap:\s*(\S+)/gim)].map(m => m[1]);
if (!sitemapsRobots.length) reportar('sitemap-roto', 'robots.txt', 'no declara ningún Sitemap:');
for (const s of sitemapsRobots) {
  let u;
  try { u = new URL(s); } catch { reportar('sitemap-roto', 'robots.txt', `dirección inválida: ${s}`); continue; }
  if (DOMINIO && u.hostname !== DOMINIO) reportar('sitemap-dominio', 'robots.txt', s);
  const destino = archivoDe(u.pathname);
  if (!destino) reportar('sitemap-roto', 'robots.txt', `apunta a un sitemap que no existe: ${s}`);
  else leerSitemap(destino);
}

// Páginas que Google podría indexar pero no están en ningún sitemap
for (const [archivo, info] of infoPagina) {
  if (info.noindex || archivo === '404.html' || enSitemap.has(archivo)) continue;
  reportar('sitemap-falta-pagina', archivo, `/${archivo}`);
}

// ── Informe ───────────────────────────────────────────────────────────────────
function esConocida(p) {
  return CONOCIDAS.verificador.find(c =>
    c.regla === p.regla && (!c.patron || new RegExp(c.patron).test(`${p.archivo} ${p.detalle}`)));
}

const nuevos = [];
const conocidos = new Map();   // entrada de fallas-conocidas → cantidad
for (const p of problemas) {
  const c = esConocida(p);
  if (c) conocidos.set(c, (conocidos.get(c) || 0) + 1);
  else nuevos.push(p);
}

const ROJO = s => process.stdout.isTTY ? `\x1b[31m${s}\x1b[0m` : s;
const AMARILLO = s => process.stdout.isTTY ? `\x1b[33m${s}\x1b[0m` : s;
const VERDE = s => process.stdout.isTTY ? `\x1b[32m${s}\x1b[0m` : s;
// Ejemplos por regla en el informe. Con --todos se muestran todos.
const MAX_EJEMPLOS = process.argv.includes('--todos') ? Infinity : 15;

console.log(`\nVerificador del sitio — ${HTMLS.length} páginas, ${records.length} discos en venta, ${vendidos.length} vendidos\n`);

if (nuevos.length) {
  console.log(ROJO(`✗ ${nuevos.length} error(es) nuevo(s):`));
  const porRegla = new Map();
  for (const p of nuevos) porRegla.set(p.regla, [...(porRegla.get(p.regla) || []), p]);
  for (const [regla, lista] of porRegla) {
    console.log(ROJO(`\n  [${regla}] ${REGLAS[regla]} — ${lista.length} caso(s)`));
    // Agrupa por lo que está mal: un link roto que aparece en 300 páginas es una sola línea.
    const porDetalle = new Map();
    for (const p of lista) porDetalle.set(p.detalle, [...(porDetalle.get(p.detalle) || []), p.archivo]);
    const grupos = [...porDetalle];
    for (const [detalle, archivos] of grupos.slice(0, MAX_EJEMPLOS)) {
      const donde = archivos.length === 1 ? archivos[0]
        : `${archivos.length} archivos (ej.: ${archivos.slice(0, 3).join(', ')})`;
      console.log(`    · ${detalle}  ←  ${donde}`);
    }
    if (grupos.length > MAX_EJEMPLOS) console.log(`    · ... y ${grupos.length - MAX_EJEMPLOS} más (correr con --todos para verlos todos)`);
  }
  console.log('');
}

if (conocidos.size) {
  console.log(AMARILLO('! Fallas conocidas (no hacen fallar la prueba; ver TESTS.md):'));
  for (const [c, n] of conocidos) console.log(AMARILLO(`  [${c.regla}] ${n} caso(s) — ${c.motivo}`));
  console.log('');
}

const yaArregladas = CONOCIDAS.verificador.filter(c => !conocidos.has(c));
if (yaArregladas.length) {
  console.log(VERDE('✓ Estas fallas conocidas ya no aparecen; se pueden sacar de fallas-conocidas.json:'));
  for (const c of yaArregladas) console.log(VERDE(`  [${c.regla}] ${c.motivo}`));
  console.log('');
}

if (process.env.INFORME_JSON) {
  fs.writeFileSync(process.env.INFORME_JSON, JSON.stringify({ nuevos, problemas }, null, 2));
}

if (nuevos.length) {
  console.log(ROJO('Resultado: HAY ERRORES NUEVOS. Revisalos antes de publicar.\n'));
  process.exit(1);
}
console.log(VERDE('Resultado: todo en orden (salvo las fallas conocidas, si las hay).\n'));
