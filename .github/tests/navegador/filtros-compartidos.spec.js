// Filtros compartidos por dirección: abrir un link como /?genero=Tango&orden=asc
// tiene que mostrar el catálogo ya filtrado, igual que lo vio quien lo compartió.
'use strict';
const fs = require('fs');
const path = require('path');
const { test, conFallasConocidas, expect, catalogo, sinAcentos, cuantosEncuentra, numero, esperarCatalogo, contador } = require('./ayuda');

const RAIZ = path.resolve(__dirname, '..', '..', '..');

test.describe('Abrir el catálogo desde una dirección con filtros', () => {
  test('?q= completa el buscador y filtra', conFallasConocidas(async ({ page }) => {
    // Una palabra del primer disco del catálogo, para que siempre haya resultados
    const palabra = catalogo()[0].artista.split(/\s+/).pop();
    await page.goto(`/?q=${encodeURIComponent(palabra)}`);
    await esperarCatalogo(page);
    await expect(page.locator('#search')).toHaveValue(palabra);
    expect(await contador(page)).toBe(cuantosEncuentra(palabra));
  }));

  test('?genero= funciona sin importar mayúsculas', conFallasConocidas(async ({ page }) => {
    await page.goto('/?genero=tango');
    await esperarCatalogo(page);
    await expect(page.locator('#filter-genre')).toHaveValue('Tango');
    expect(await contador(page)).toBe(catalogo().filter(r => r.genero === 'Tango').length);
  }));

  test('varios filtros juntos: género, década, tipo y orden', conFallasConocidas(async ({ page }) => {
    await page.goto('/?genero=Rock&decada=1980&tipo=Compilados&orden=asc');
    await esperarCatalogo(page);
    await expect(page.locator('#filter-genre')).toHaveValue('Rock');
    await expect(page.locator('#filter-decade')).toHaveValue('1980');
    await expect(page.locator('#filter-tipo')).toHaveValue('Compilados');
    await expect(page.locator('#filter-sort')).toHaveValue('asc');
    const esperado = catalogo().filter(r => {
      const y = parseInt(r.anio, 10);
      return r.genero === 'Rock' && y >= 1980 && y < 1990 && (r.tipos || []).includes('Compilados');
    }).length;
    expect(await contador(page)).toBe(esperado);
    const precios = (await page.locator('#grid .card-price').allTextContents()).map(numero);
    expect(precios).toEqual([...precios].sort((a, b) => a - b));
  }));

  test('un valor que no existe se ignora sin romper la página', conFallasConocidas(async ({ page }) => {
    await page.goto('/?genero=NoExiste&decada=1850&orden=cualquiera');
    await esperarCatalogo(page);
    await expect(page.locator('#filter-genre')).toHaveValue('');
    expect(await contador(page)).toBe(catalogo().length);
  }));

  test('?artista= muestra el cartel y "Ver todo el catálogo" lo saca', conFallasConocidas(async ({ page }) => {
    // Un artista sin página propia (los que usan /?artista=...)
    const r = catalogo().find(x => (x.artistaUrl || '').startsWith('/?artista='));
    const slug = r.artistaSlug;
    await page.goto(`/?artista=${slug}`);
    await esperarCatalogo(page);
    await expect(page.locator('#aviso-artista')).toBeVisible();
    expect(await contador(page)).toBe(catalogo().filter(x => x.artistaSlug === slug).length);
    await page.locator('#quitar-artista').click();
    await expect(page.locator('#aviso-artista')).toHaveCount(0);
    await expect(page).not.toHaveURL(/artista=/);
    await expect.poll(() => contador(page)).toBe(catalogo().length);
  }));

  test('?id= abre directamente la ventana del disco', conFallasConocidas(async ({ page }) => {
    const r = catalogo()[0];
    const id = r.url.match(/MLA-?(\d+)/)[1];
    await page.goto(`/?id=${id}`);
    await expect(page.locator('#modal-overlay')).toHaveClass(/open/);
    await expect(page.locator('#modal-title')).toHaveText(r.titulo);
    // Cerrar la ventana saca el id de la dirección
    await page.locator('#modal-close').click();
    await expect(page.locator('#modal-overlay')).not.toHaveClass(/open/);
    await expect(page).not.toHaveURL(/id=/);
  }));

  test('?id=MLA... (con letras, como en Mercado Libre) también abre el disco', conFallasConocidas(async ({ page }) => {
    const r = catalogo()[0];
    await page.goto(`/?id=MLA${r.url.match(/MLA-?(\d+)/)[1]}`);
    await expect(page.locator('#modal-overlay')).toHaveClass(/open/);
    await expect(page.locator('#modal-title')).toHaveText(r.titulo);
  }));

  test('caracteres raros en la búsqueda no rompen nada ni se interpretan como código', conFallasConocidas(async ({ page }) => {
    const texto = '<b>"100%" & AC/DC</b>';
    await page.goto(`/?q=${encodeURIComponent(texto)}`);
    await expect(page.locator('#search')).toHaveValue(texto);
    await expect(page.locator('#empty')).toBeVisible();
    await expect(page.locator('#grid b, .filters-bar b')).toHaveCount(0);
    // Y la dirección conserva el texto tal cual para compartirlo
    await expect(page).toHaveURL(u => u.searchParams.get('q') === texto);
  }));

  test('lo que se ve se puede compartir: la dirección reproduce el mismo resultado', conFallasConocidas(async ({ page, context }) => {
    await page.goto('/');
    await esperarCatalogo(page);
    await page.locator('#filter-genre').selectOption('Melódico');
    await page.locator('#filter-sort').selectOption('desc');
    await page.locator('#search').fill('amor');
    await expect(page).toHaveURL(/q=amor/);
    await expect.poll(() => contador(page)).toBe(
      catalogo().filter(r => r.genero === 'Melódico' && cuantosEncuentraUno(r, 'amor')).length);
    const cantidad = await contador(page);
    const primeros = await page.locator('#grid .card-album').evaluateAll(els => els.slice(0, 5).map(e => e.textContent));

    // Otra pestaña, como si fuera otra persona abriendo el link
    const otra = await context.newPage();
    await otra.route(/^https?:\/\/(?!127\.0\.0\.1|localhost)/, ruta => ruta.abort());
    await otra.goto(page.url());
    await esperarCatalogo(otra);
    await expect(otra.locator('#search')).toHaveValue('amor');
    await expect(otra.locator('#filter-genre')).toHaveValue('Melódico');
    await expect(otra.locator('#filter-sort')).toHaveValue('desc');
    expect(await contador(otra)).toBe(cantidad);
    const primerosOtra = await otra.locator('#grid .card-album').evaluateAll(els => els.slice(0, 5).map(e => e.textContent));
    expect(primerosOtra).toEqual(primeros);
  }));
});

// Los links del sitio que abren el catálogo filtrado (botones de las páginas de
// colección y de década) tienen que mostrar discos, no un catálogo vacío.
const LINKS_FILTRADOS = (() => {
  const salida = new Map();
  const paginas = fs.readdirSync(RAIZ).filter(f => f.endsWith('.html'))
    .concat(fs.readdirSync(path.join(RAIZ, 'decada')).map(f => `decada/${f}`));
  for (const p of paginas) {
    const html = fs.readFileSync(path.join(RAIZ, p), 'utf8');
    for (const m of html.matchAll(/href="(\/\?[^"]+)"/g)) {
      const href = m[1].replace(/&amp;/g, '&');
      if (!salida.has(href)) salida.set(href, p);
    }
  }
  return [...salida];
})();

test.describe('Links del sitio que abren el catálogo filtrado', () => {
  for (const [href, pagina] of LINKS_FILTRADOS) {
    test(`${pagina} → ${href} muestra discos`, conFallasConocidas(async ({ page }) => {
      await page.goto(href);
      await esperarCatalogo(page);
      expect(await contador(page)).toBeGreaterThan(0);
      expect(await contador(page)).toBeLessThan(catalogo().length);
    }));
  }
});

function cuantosEncuentraUno(r, texto) {
  return sinAcentos(`${r.titulo} ${r.artista} ${r.album}`).includes(sinAcentos(texto));
}
