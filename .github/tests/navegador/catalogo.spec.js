// Catálogo (portada): carga, búsqueda y filtros.
'use strict';
const { test, conFallasConocidas, expect, catalogo, sinAcentos, cuantosEncuentra, numero, esperarCatalogo, contador } = require('./ayuda');

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await esperarCatalogo(page);
});

test.describe('Carga del catálogo', () => {
  test('muestra todos los discos de records.json y la primera tanda de 60', conFallasConocidas(async ({ page }) => {
    expect(await contador(page)).toBe(catalogo().length);
    await expect(page.locator('#grid .card')).toHaveCount(60);
    await expect(page.locator('#load-more')).toBeVisible();
  }));

  test('"Cargar más discos" agrega otra tanda', conFallasConocidas(async ({ page }) => {
    await page.locator('#load-more').click();
    await expect(page.locator('#grid .card')).toHaveCount(120);
  }));

  test('cada tarjeta tiene artista, álbum, precio y link a su ficha', conFallasConocidas(async ({ page }) => {
    const tarjetas = page.locator('#grid .card');
    for (let i = 0; i < 10; i++) {
      const t = tarjetas.nth(i);
      await expect(t.locator('.card-artist')).not.toBeEmpty();
      await expect(t.locator('.card-album')).not.toBeEmpty();
      await expect(t.locator('.card-price')).toHaveText(/^\$ [\d.]+$/);
      await expect(t.locator('.card-artist')).toHaveAttribute('href', /^\/disco\/.+\.html$/);
      await expect(t.locator('.btn-card-direct')).toHaveAttribute('href', /^https:\/\/wa\.me\//);
    }
  }));

  test('los filtros traen las opciones del catálogo', conFallasConocidas(async ({ page }) => {
    const generos = new Set(catalogo().map(r => r.genero).filter(Boolean));
    // +1 por la opción "Todos los géneros"
    await expect(page.locator('#filter-genre option')).toHaveCount(generos.size + 1);
    await expect(page.locator('#filter-tipo option')).not.toHaveCount(1);
  }));
});

test.describe('Búsqueda', () => {
  const buscar = async (page, texto) => {
    await page.locator('#search').fill(texto);
    // El buscador espera un instante después de la última tecla; esperamos a
    // que la dirección muestre exactamente este texto para saber que ya filtró.
    await expect(page).toHaveURL(u => u.searchParams.get('q') === texto.trim());
  };

  // Un artista del catálogo actual con tilde y dos palabras (por ejemplo "León
  // Gieco"). Se elige al correr, así el test no depende de un disco puntual.
  const artista = () => catalogo().map(r => r.artista)
    .find(a => /[áéíóúñ]/i.test(a || '') && a.trim().split(/\s+/).length === 2);
  const sinTilde = () => sinAcentos(artista());                      // "leon gieco"
  const apellido = () => sinTilde().split(' ')[1];                   // "gieco"
  const alReves  = () => sinTilde().split(' ').reverse().join(' ');  // "gieco leon"

  test('encuentra la cantidad correcta de discos', conFallasConocidas(async ({ page }) => {
    await buscar(page, apellido());
    const esperado = cuantosEncuentra(apellido());
    expect(esperado).toBeGreaterThan(0);
    await expect.poll(() => contador(page)).toBe(esperado);
  }));

  test('no distingue tildes ni mayúsculas', conFallasConocidas(async ({ page }) => {
    await buscar(page, artista().toUpperCase());          // "LEÓN GIECO"
    const conTilde = await contador(page);
    expect(conTilde).toBeGreaterThan(0);
    await buscar(page, sinTilde());                       // "leon gieco"
    await expect.poll(() => contador(page)).toBe(conTilde);
    expect(conTilde).toBe(cuantosEncuentra(sinTilde()));
  }));

  test('el orden de las palabras no importa', conFallasConocidas(async ({ page }) => {
    await buscar(page, alReves());
    await expect.poll(() => contador(page)).toBe(cuantosEncuentra(sinTilde()));
  }));

  test('sin resultados muestra el aviso y oculta "Cargar más"', conFallasConocidas(async ({ page }) => {
    await buscar(page, 'zzqqxxwwyy');
    await expect(page.locator('#empty')).toBeVisible();
    await expect(page.locator('#grid .card')).toHaveCount(0);
    await expect(page.locator('#load-more')).toBeHidden();
    expect(await contador(page)).toBe(0);
  }));

  test('borrar la búsqueda vuelve a mostrar todo y limpia la dirección', conFallasConocidas(async ({ page }) => {
    await buscar(page, apellido());
    await page.locator('#search').fill('');
    await expect(page).not.toHaveURL(/[?&]q=/);
    await expect.poll(() => contador(page)).toBe(catalogo().length);
  }));
});

test.describe('Filtros', () => {
  test('género: filtra y queda en la dirección', conFallasConocidas(async ({ page }) => {
    await page.locator('#filter-genre').selectOption('Tango');
    await expect(page).toHaveURL(/genero=Tango/);
    const esperado = catalogo().filter(r => r.genero === 'Tango').length;
    await expect.poll(() => contador(page)).toBe(esperado);
  }));

  test('origen: filtra y queda en la dirección', conFallasConocidas(async ({ page }) => {
    await page.locator('#filter-origin').selectOption('Brasil');
    await expect(page).toHaveURL(/origen=Brasil/);
    const esperado = catalogo().filter(r => r.origen === 'Brasil').length;
    await expect.poll(() => contador(page)).toBe(esperado);
  }));

  test('década: filtra por años y queda en la dirección', conFallasConocidas(async ({ page }) => {
    await page.locator('#filter-decade').selectOption('1970');
    await expect(page).toHaveURL(/decada=1970/);
    const esperado = catalogo().filter(r => { const y = parseInt(r.anio, 10); return y >= 1970 && y < 1980; }).length;
    await expect.poll(() => contador(page)).toBe(esperado);
    const anios = await page.locator('#grid .card-year').allTextContents();
    for (const a of anios) {
      expect(Number(a)).toBeGreaterThanOrEqual(1970);
      expect(Number(a)).toBeLessThan(1980);
    }
  }));

  test('tipo de edición: filtra y queda en la dirección', conFallasConocidas(async ({ page }) => {
    await page.locator('#filter-tipo').selectOption('Compilados');
    await expect(page).toHaveURL(/tipo=Compilados/);
    const esperado = catalogo().filter(r => (r.tipos || []).includes('Compilados')).length;
    await expect.poll(() => contador(page)).toBe(esperado);
  }));

  test('orden por precio: de menor a mayor y de mayor a menor', conFallasConocidas(async ({ page }) => {
    const precios = async () => (await page.locator('#grid .card-price').allTextContents()).map(numero);
    await page.locator('#filter-sort').selectOption('asc');
    await expect(page).toHaveURL(/orden=asc/);
    let p = await precios();
    expect(p).toEqual([...p].sort((a, b) => a - b));
    await page.locator('#filter-sort').selectOption('desc');
    await expect(page).toHaveURL(/orden=desc/);
    p = await precios();
    expect(p).toEqual([...p].sort((a, b) => b - a));
  }));

  test('filtros combinados con búsqueda', conFallasConocidas(async ({ page }) => {
    await page.locator('#filter-genre').selectOption('Rock');
    await page.locator('#filter-decade').selectOption('1980');
    await page.locator('#search').fill('queen');
    await expect(page).toHaveURL(/q=queen/);
    const esperado = catalogo().filter(r => {
      const y = parseInt(r.anio, 10);
      return r.genero === 'Rock' && y >= 1980 && y < 1990 &&
        `${r.titulo} ${r.artista} ${r.album}`.toLowerCase().includes('queen');
    }).length;
    await expect.poll(() => contador(page)).toBe(esperado);
  }));

  test('"Limpiar" vuelve todo a cero, también la dirección', conFallasConocidas(async ({ page }) => {
    await page.locator('#filter-genre').selectOption('Tango');
    await page.locator('#filter-sort').selectOption('asc');
    await page.locator('#search').fill('orquesta');
    await expect(page).toHaveURL(/q=orquesta/);
    await page.locator('#btn-reset').click();
    await expect(page.locator('#search')).toHaveValue('');
    await expect(page.locator('#filter-genre')).toHaveValue('');
    await expect(page.locator('#filter-sort')).toHaveValue('new');
    await expect(page).toHaveURL(/\/$/);
    await expect.poll(() => contador(page)).toBe(catalogo().length);
  }));
});
