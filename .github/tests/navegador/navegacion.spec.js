// Navegación entre catálogo, ficha de disco y página de artista.
// Los discos se eligen del catálogo actual (no con números fijos), así los
// tests siguen andando aunque se vendan discos o entren nuevos.
'use strict';
const { test, conFallasConocidas, expect, catalogo, vendidos, numero, esperarCatalogo, contador, anchoExcedido } = require('./ayuda');

const idDe = r => r.url.match(/MLA-?(\d+)/)[1];
// Un disco cuyo artista tiene página propia
const conArtista = () => catalogo().find(r => (r.artistaUrl || '').startsWith('/artista/'));

test.describe('Catálogo → ventana del disco', () => {
  test('tocar una tarjeta abre la ventana del disco y Escape/✕ la cierra', conFallasConocidas(async ({ page }) => {
    await page.goto('/');
    await esperarCatalogo(page);
    const tarjeta = page.locator('#grid .card').first();
    const album = (await tarjeta.locator('.card-album').textContent()).trim();
    await tarjeta.locator('.card-album').click();
    await expect(page.locator('#modal-overlay')).toHaveClass(/open/);
    await expect(page).toHaveURL(/[?&]id=\d+/);
    await expect(page.locator('#modal-title')).toContainText(album.split(' ')[0]);
    await expect(page.locator('#modal-price')).toHaveText(/^\$ [\d.]+$/);
    await expect(page.locator('#modal-btn-wa')).toHaveAttribute('href', /^https:\/\/wa\.me\/\d+\?text=/);
    await expect(page.locator('#modal-btn-mail')).toHaveAttribute('href', /^mailto:/);
    await page.locator('#modal-close').click();
    await expect(page.locator('#modal-overlay')).not.toHaveClass(/open/);
    await expect(page).not.toHaveURL(/[?&]id=/);
    // También se cierra con la tecla Escape
    await tarjeta.locator('.card-album').click();
    await expect(page.locator('#modal-overlay')).toHaveClass(/open/);
    await page.keyboard.press('Escape');
    await expect(page.locator('#modal-overlay')).not.toHaveClass(/open/);
  }));

  test('los discos relacionados de la ventana abren otro disco', conFallasConocidas(async ({ page }) => {
    const r = catalogo()[0];
    await page.goto(`/?id=${idDe(r)}`);
    await expect(page.locator('#modal-overlay')).toHaveClass(/open/);
    const rel = page.locator('#modal-related .related-card').first();
    await expect(rel).toBeVisible();
    const album = (await rel.locator('.related-card-album').textContent()).trim();
    await rel.click();
    await expect(page.locator('#modal-title')).toContainText(album.split(' ')[0]);
    await expect(page).not.toHaveURL(new RegExp(`id=${idDe(r)}`));
  }));

  test('desde la ventana, el nombre del artista lleva a su página', conFallasConocidas(async ({ page }) => {
    const r = conArtista();
    await page.goto(`/?id=${idDe(r)}`);
    await expect(page.locator('#modal-overlay')).toHaveClass(/open/);
    await page.locator('#modal-artist a').click();
    await expect(page).toHaveURL(new RegExp(`${r.artistaUrl.replace(/\./g, '\\.')}$`));
    await expect(page.locator('h1')).toContainText(r.artista);
  }));

  test('el link de la tarjeta lleva a la ficha del disco (abrir en pestaña nueva)', conFallasConocidas(async ({ page }) => {
    await page.goto('/');
    await esperarCatalogo(page);
    const href = await page.locator('#grid .card .card-album').first().getAttribute('href');
    const album = (await page.locator('#grid .card .card-album').first().textContent()).trim();
    const resp = await page.goto(href);
    expect(resp.status()).toBe(200);
    await expect(page.locator('h1')).toHaveText(album);
  }));
});

test.describe('Ficha del disco', () => {
  test('muestra título, precio, botones de contacto y vuelve al catálogo', conFallasConocidas(async ({ page }) => {
    const r = conArtista();
    const resp = await page.goto(`/disco/${r.ficha}`);
    expect(resp.status()).toBe(200);
    await expect(page.locator('h1')).toHaveText(r.album);
    await expect(page.locator('.f-price')).toHaveText(/^\$ [\d.]+$/);
    const wa = page.locator('.f-btn-wa');
    await expect(wa).toHaveAttribute('href', /^https:\/\/wa\.me\/\d+\?text=/);
    // El mensaje de WhatsApp incluye el link a esta misma ficha
    expect(decodeURIComponent(await wa.getAttribute('href'))).toContain(`/disco/${r.ficha}`);
    await expect(page.locator('.f-btn-ml')).toHaveAttribute('href', new RegExp(idDe(r)));

    await page.locator('.f-breadcrumb a', { hasText: 'Catálogo' }).click();
    await esperarCatalogo(page);
    expect(await contador(page)).toBe(catalogo().length);
  }));

  test('el precio de la ficha es el mismo que el del catálogo', conFallasConocidas(async ({ page }) => {
    const r = conArtista();
    await page.goto(`/?id=${idDe(r)}`);
    await expect(page.locator('#modal-overlay')).toHaveClass(/open/);
    const enCatalogo = numero(await page.locator('#modal-price').textContent());
    await page.goto(`/disco/${r.ficha}`);
    expect(numero(await page.locator('.f-price').textContent())).toBe(enCatalogo);
  }));

  test('el género de la miga de pan abre el catálogo filtrado', conFallasConocidas(async ({ page }) => {
    const r = conArtista();
    await page.goto(`/disco/${r.ficha}`);
    const link = page.locator('.f-breadcrumb a').nth(1);
    await expect(link).toHaveAttribute('href', /\/\?genero=/);
    await link.click();
    await esperarCatalogo(page);
    await expect(page.locator('#filter-genre')).toHaveValue(r.genero);
    expect(await contador(page)).toBe(catalogo().filter(x => x.genero === r.genero).length);
  }));

  test('ficha → artista → otro disco del artista', conFallasConocidas(async ({ page }) => {
    const r = conArtista();
    await page.goto(`/disco/${r.ficha}`);
    await page.locator('.f-artist a').click();
    await expect(page).toHaveURL(new RegExp(`${r.artistaUrl.replace(/\./g, '\\.')}$`));
    await expect(page.locator('h1')).toContainText(r.artista);
    // La página del artista lista este disco
    await expect(page.locator(`a.h-card[href="/disco/${r.ficha}"]`)).toHaveCount(1);
    const cantidad = catalogo().filter(x => x.artistaSlug === r.artistaSlug).length;
    await expect(page.locator('a.h-card')).toHaveCount(cantidad);
    // Y desde ahí se puede entrar a cualquiera de sus discos
    const otro = page.locator('a.h-card').last();
    const album = (await otro.locator('.h-card-album').textContent()).trim();
    await otro.click();
    await expect(page.locator('h1')).toHaveText(album);
  }));

  test('los discos relacionados de la ficha llevan a otras fichas', conFallasConocidas(async ({ page }) => {
    const r = conArtista();
    await page.goto(`/disco/${r.ficha}`);
    const rel = page.locator('a.f-rel-card').first();
    await expect(rel).toBeVisible();
    const album = (await rel.locator('.f-rel-album').textContent()).trim();
    await rel.click();
    await expect(page.locator('h1')).toHaveText(album);
  }));

  test('el link para compartir (/d/...) redirige a la ficha', conFallasConocidas(async ({ page }) => {
    const r = conArtista();
    await page.goto(`/d/${idDe(r)}.html`);
    await expect(page).toHaveURL(new RegExp(`/disco/${r.ficha.replace(/\./g, '\\.')}$`));
    await expect(page.locator('h1')).toHaveText(r.album);
  }));
});

test.describe('Disco vendido', () => {
  const vendido = () => vendidos().find(r => r.ficha);

  test('su ficha sigue existiendo y avisa que se vendió', conFallasConocidas(async ({ page }) => {
    const r = vendido();
    test.skip(!r, 'No hay discos vendidos en vendidos.json');
    const resp = await page.goto(`/disco/${r.ficha}`);
    expect(resp.status()).toBe(200);
    await expect(page.locator('.f-sold-badge')).toHaveText('Vendido');
    await expect(page.locator('.f-sold-banner')).toBeVisible();
    // Sigue habiendo forma de consultar (por si entra otra copia)
    await expect(page.locator('.f-sold-banner a[href^="https://wa.me/"]')).toHaveCount(1);
  }));

  test('no aparece en el catálogo', conFallasConocidas(async ({ page }) => {
    const r = vendido();
    test.skip(!r, 'No hay discos vendidos en vendidos.json');
    await page.goto(`/?id=${r.url.match(/MLA-?(\d+)/)[1]}`);
    await esperarCatalogo(page);
    await expect(page.locator('#modal-overlay')).not.toHaveClass(/open/);
  }));
});

test.describe('Páginas de colección y error', () => {
  test('Melódico: el contador se actualiza con el catálogo', conFallasConocidas(async ({ page }) => {
    await page.goto('/melodico.html');
    const esperado = catalogo().filter(r => r.genero === 'Melódico').length;
    await expect.poll(async () => numero(await page.locator('#melo-count').textContent())).toBe(esperado);
  }));

  test('colecciones → página de década → catálogo filtrado por década', conFallasConocidas(async ({ page }) => {
    await page.goto('/colecciones.html');
    await page.locator('a[href="/decada/1970.html"]').first().click();
    await expect(page).toHaveURL(/\/decada\/1970\.html$/);
    await page.locator('a[href="/?decada=1970"]').first().click();
    await esperarCatalogo(page);
    await expect(page.locator('#filter-decade')).toHaveValue('1970');
  }));

  test('una dirección que no existe muestra la página de error con salida al catálogo', conFallasConocidas(async ({ page }) => {
    const resp = await page.goto('/disco/no-existe-este-disco.html');
    expect(resp.status()).toBe(404);
    await expect(page.locator('h1')).toHaveText('Esta página no existe');
    await page.locator('a.btn').click();
    await esperarCatalogo(page);
  }));
});

// En el celular nada tiene que salirse de la pantalla hacia los costados.
test.describe('Nada se sale de la pantalla', () => {
  const PAGINAS = [
    ['catálogo', () => '/'],
    ['ficha de disco', () => `/disco/${conArtista().ficha}`],
    ['página de artista', () => conArtista().artistaUrl],
    ['colecciones', () => '/colecciones.html'],
    ['década', () => '/decada/1980.html'],
    ['rock nacional', () => '/rock-nacional.html'],
  ];
  for (const [nombre, url] of PAGINAS) {
    test(`${nombre}: sin desplazamiento horizontal`, conFallasConocidas(async ({ page }) => {
      await page.goto(url());
      if (url() === '/') await esperarCatalogo(page);
      expect(await anchoExcedido(page)).toBeLessThanOrEqual(0);
    }));
  }

  test('catálogo: el buscador y todos los filtros se ven y entran en la pantalla', conFallasConocidas(async ({ page }) => {
    await page.goto('/');
    await esperarCatalogo(page);
    const ancho = page.viewportSize().width;
    for (const sel of ['#search', '#filter-genre', '#filter-origin', '#filter-decade', '#filter-tipo', '#filter-sort', '#btn-reset']) {
      const el = page.locator(sel);
      await el.scrollIntoViewIfNeeded();
      await expect(el, sel).toBeVisible();
      const caja = await el.boundingBox();
      expect(caja.x, `${sel} empieza fuera de la pantalla`).toBeGreaterThanOrEqual(0);
      expect(caja.x + caja.width, `${sel} se sale por la derecha`).toBeLessThanOrEqual(ancho + 1);
    }
  }));

  test('ventana del disco: entra en la pantalla y se puede cerrar', conFallasConocidas(async ({ page }) => {
    const r = catalogo()[0];
    await page.goto(`/?id=${idDe(r)}`);
    await expect(page.locator('#modal-overlay')).toHaveClass(/open/);
    const caja = await page.locator('.modal').boundingBox();
    const vista = page.viewportSize();
    expect(caja.x).toBeGreaterThanOrEqual(0);
    expect(caja.x + caja.width).toBeLessThanOrEqual(vista.width + 1);
    await expect(page.locator('#modal-close')).toBeInViewport();
    await page.locator('#modal-close').click();
    await expect(page.locator('#modal-overlay')).not.toHaveClass(/open/);
  }));
});
