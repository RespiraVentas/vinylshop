// Herramientas compartidas por los tests de navegador.
'use strict';
const fs = require('fs');
const path = require('path');
const base = require('@playwright/test');

const RAIZ = path.resolve(__dirname, '..', '..', '..');
const CONOCIDAS = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'fallas-conocidas.json'), 'utf8')).navegador;

// ── Datos del catálogo, leídos del mismo archivo que usa el sitio ─────────────
let cache;
function catalogo() {
  if (!cache) cache = JSON.parse(fs.readFileSync(path.join(RAIZ, 'data', 'records.json'), 'utf8').replace(/^\uFEFF/, ''));
  return cache;
}

let cacheVendidos;
function vendidos() {
  const f = path.join(RAIZ, 'data', 'vendidos.json');
  if (!cacheVendidos) cacheVendidos = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8').replace(/^\uFEFF/, '')) : [];
  return cacheVendidos;
}

// Igual criterio que el buscador: sin tildes y en minúsculas.
const sinAcentos = s => (s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

// Cuántos discos debería encontrar el buscador para un texto (palabra por palabra).
function cuantosEncuentra(texto) {
  const palabras = sinAcentos(texto).trim().split(/\s+/).filter(Boolean);
  return catalogo().filter(r => {
    const t = sinAcentos(`${r.titulo || ''} ${r.artista || ''} ${r.album || ''}`);
    return palabras.every(p => t.includes(p));
  }).length;
}

const numero = texto => Number(String(texto).replace(/\D/g, ''));

// ── Test con dos agregados automáticos ────────────────────────────────────────
// 1. Bloquea todo lo que no sea el sitio local (fuentes de Google, fotos de
//    Mercado Libre...). Así los tests no dependen de internet y son rápidos.
// 2. Junta los errores de JavaScript de la página: si aparece uno, el test falla.
const test = base.test.extend({
  page: async ({ page }, use) => {
    await page.route(/^https?:\/\/(?!127\.0\.0\.1|localhost)/, ruta => ruta.abort());
    const errores = [];
    page.on('pageerror', e => errores.push(e.message));
    await use(page);
    base.expect(errores, 'Errores de JavaScript en la página').toEqual([]);
  },
});

// conFallasConocidas(): envuelve el cuerpo de cada test. Si el título del test
// figura en fallas-conocidas.json y falla, queda como "salteado: falla conocida"
// en vez de dejar todo en rojo. Si una falla conocida deja de fallar, lo avisa
// para sacarla de la lista. Para los demás tests no cambia nada.
//   test('título', conFallasConocidas(async ({ page }) => { ... }));
function conFallasConocidas(cuerpo) {
  // Playwright mira qué "fixtures" pide el test: page y context alcanzan para todos.
  return async ({ page, context }, info) => {
    const conocida = CONOCIDAS.find(c => c.test === info.title);
    if (!conocida) return cuerpo({ page, context }, info);
    try {
      await cuerpo({ page, context }, info);
    } catch (e) {
      if (info.expectedStatus === 'skipped') throw e;   // un test.skip() del propio test
      info.annotations.push({ type: 'falla conocida', description: conocida.motivo });
      test.skip(true, `Falla conocida: ${conocida.motivo}`);
    }
    info.annotations.push({
      type: 'falla conocida que ya no falla',
      description: `"${info.title}" pasó: si sigue así, sacarlo de fallas-conocidas.json`,
    });
    console.log(`\n  ✓ "${info.title}" figura como falla conocida pero pasó. Se puede sacar de fallas-conocidas.json.`);
  };
}

// Espera a que el catálogo termine de cargar y dibujar la primera tanda.
async function esperarCatalogo(page) {
  await base.expect(page.locator('#grid .card').first()).toBeVisible();
  await base.expect(page.locator('#count')).toHaveText(/\d/);
}

const contador = async page => numero(await page.locator('#count').textContent());

// Página sin desplazamiento horizontal (nada se sale de la pantalla).
async function anchoExcedido(page) {
  return page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
}

module.exports = {
  test, expect: base.expect, conFallasConocidas, catalogo, vendidos, sinAcentos, cuantosEncuentra,
  numero, esperarCatalogo, contador, anchoExcedido,
};
