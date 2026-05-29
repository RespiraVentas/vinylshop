'use strict';

const PAGE_SIZE  = 60;
const WA_NUMBER  = '5493416068888';
const MAIL_TO    = 'revistarespiraok@gmail.com';

let allRecords = [];
let filtered   = [];
let displayed  = 0;

const PLACEHOLDER = `<svg viewBox="0 0 64 64" fill="none">
  <circle cx="32" cy="32" r="28" stroke="#ddd" stroke-width="2"/>
  <circle cx="32" cy="32" r="4" fill="#ddd"/>
</svg>`;

const WA_ICON = `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/></svg>`;

// ── DOM ───────────────────────────────────────────────────────────────────────
const grid         = document.getElementById('grid');
const searchInput  = document.getElementById('search');
const filterGenre  = document.getElementById('filter-genre');
const filterOrigin = document.getElementById('filter-origin');
const filterDecade = document.getElementById('filter-decade');
const filterSort   = document.getElementById('filter-sort');
const btnReset     = document.getElementById('btn-reset');
const btnLoadMore  = document.getElementById('load-more');
const countEl      = document.getElementById('count');
const emptyEl      = document.getElementById('empty');
const loadingEl    = document.getElementById('loading');
const overlay      = document.getElementById('modal-overlay');
const modalClose   = document.getElementById('modal-close');

// ── Init ──────────────────────────────────────────────────────────────────────
async function init() {
  try {
    loadingEl.style.display = 'flex';
    const res = await fetch('data/records.json');
    if (!res.ok) throw new Error(res.statusText);
    const raw = await res.json();
    allRecords = raw.map(normalize);
    computeNewSet();
    populateSelects();
    applyFilters();
  } catch (e) {
    loadingEl.style.display = 'none';
    grid.innerHTML = `<p style="padding:60px;color:#c00;grid-column:1/-1">
      Error al cargar: ${e.message}</p>`;
  }
}

function normalize(r) {
  const lines = (r.desc || '').split('\n');
  let disco = '', tapa = '';
  for (const line of lines.slice(0, 5)) {
    const l = line.trim();
    if (/^disco\s*:/i.test(l)) disco = l.replace(/^disco\s*:\s*/i, '').trim();
    if (/^tapa\s*:/i.test(l))  tapa  = l.replace(/^tapa\s*:\s*/i, '').trim();
  }

  // Si el artista está vacío, lo extrae del título (formato: "Artista - Álbum - ...")
  let artista = r.artista;
  if (!artista && r.titulo) {
    const partes = r.titulo.split(' - ');
    if (partes.length >= 2) artista = partes[0].trim();
  }

  return { ...r, artista, disco, tapa };
}

function populateSelects() {
  [...new Set(allRecords.map(r => r.genero).filter(Boolean))].sort()
    .forEach(g => filterGenre.add(new Option(g, g)));
  [...new Set(allRecords.map(r => r.origen).filter(Boolean))].sort()
    .forEach(o => filterOrigin.add(new Option(o, o)));
}

// ── Filtros ───────────────────────────────────────────────────────────────────
function applyFilters() {
  const q      = searchInput.value.trim().toLowerCase();
  const genre  = filterGenre.value;
  const origin = filterOrigin.value;
  const decade = filterDecade.value ? parseInt(filterDecade.value, 10) : null;

  const sort = filterSort.value;

  filtered = allRecords.filter(r => {
    if (q && !`${r.titulo} ${r.artista} ${r.album}`.toLowerCase().includes(q)) return false;
    if (genre  && r.genero !== genre)  return false;
    if (origin && r.origen !== origin) return false;
    if (decade !== null) {
      const y = parseInt(r.anio, 10);
      if (isNaN(y) || y < decade || y >= decade + 10) return false;
    }
    return true;
  });

  if (sort === 'asc')    filtered.sort((a, b) => (a.precio || 0) - (b.precio || 0));
  if (sort === 'desc')   filtered.sort((a, b) => (b.precio || 0) - (a.precio || 0));
  if (sort === 'visits') filtered.sort((a, b) => (b.visitas || 0) - (a.visitas || 0));
  if (sort === 'new' || sort === '') filtered.sort((a, b) => {
    // Compara como strings ISO (yyyy-MM-ddTHH:mm:ss) — orden lexicográfico = cronológico
    if (!a.fecha && !b.fecha) return 0;
    if (!a.fecha) return 1;
    if (!b.fecha) return -1;
    return b.fecha.localeCompare(a.fecha);
  });

  displayed = 0;
  grid.innerHTML = '';
  emptyEl.style.display = 'none';
  countEl.textContent = `${filtered.length.toLocaleString('es-AR')} discos`;
  renderBatch();
}

function renderBatch() {
  loadingEl.style.display = 'flex';
  requestAnimationFrame(() => {
    const batch = filtered.slice(displayed, displayed + PAGE_SIZE);

    if (batch.length === 0 && displayed === 0) {
      emptyEl.style.display = 'block';
      loadingEl.style.display = 'none';
      btnLoadMore.style.display = 'none';
      return;
    }

    const frag = document.createDocumentFragment();
    batch.forEach(r => frag.appendChild(createCard(r)));
    grid.appendChild(frag);
    displayed += batch.length;

    loadingEl.style.display = 'none';
    btnLoadMore.style.display = displayed < filtered.length ? 'block' : 'none';
  });
}

// ── Badge "Nuevo" ─────────────────────────────────────────────────────────────
const NEW_BADGE_COUNT  = 80;   // máximo de badges a mostrar
const NEW_MAX_DAYS_MS  = 30 * 24 * 60 * 60 * 1000;

let newSet = new Set();

function computeNewSet() {
  newSet.clear();
  // Ordenar los que tienen fecha, de más nuevo a más viejo
  const withDate = allRecords
    .filter(r => r.fecha)
    .sort((a, b) => b.fecha.localeCompare(a.fecha));

  if (!withDate.length) return;

  // Si el más reciente tiene más de 30 días → sin badges
  const mostRecent = new Date(withDate[0].fecha).getTime();
  if (Date.now() - mostRecent > NEW_MAX_DAYS_MS) return;

  // Los primeros NEW_BADGE_COUNT más recientes llevan badge
  withDate.slice(0, NEW_BADGE_COUNT).forEach(r => newSet.add(r));
}

function isNew(r) { return newSet.has(r); }

// ── Card ──────────────────────────────────────────────────────────────────────
function createCard(r) {
  const card = document.createElement('article');
  card.className = 'card';

  const imgSrc = r.imagenes?.[0];
  const badgeHTML = isNew(r) ? `<span class="badge-new">Nuevo</span>` : '';
  const imgHTML = imgSrc
    ? `${badgeHTML}<div class="card-img-inner" style="background-image:url('${esc(imgSrc)}')"></div>`
    : `${badgeHTML}<div class="card-img-inner card-placeholder">${PLACEHOLDER}</div>`;

  const price = r.precio ? `$ ${r.precio.toLocaleString('es-AR')}` : '';

  // Links de WhatsApp y mail con mensaje preescrito incluyendo link ML
  const { waHref, mailHref } = buildContactLinks(r);

  card.innerHTML = `
    <div class="card-img-wrap">
      ${imgHTML}
    </div>
    <div class="card-body">
      <div class="card-artist">${esc(r.artista || '—')}</div>
      <div class="card-album">${esc(r.album || r.titulo || '')}</div>
      <div class="card-row">
        <span class="card-price">${price}</span>
        <span class="card-year">${esc(r.anio || '')}</span>
      </div>
      <div class="card-buttons">
        <a class="btn-card-direct" href="${waHref}" target="_blank" rel="noopener"
           onclick="event.stopPropagation()">
          ${WA_ICON} Contactar (10% dto.)
        </a>
        <a class="btn-card-ml" href="${esc(r.url || '#')}" target="_blank" rel="noopener"
           onclick="event.stopPropagation()">
          Ver en Mercado Libre
        </a>
      </div>
    </div>`;

  // Clic en imagen o texto → abre modal
  card.querySelector('.card-img-wrap').addEventListener('click', () => openModal(r));
  card.querySelector('.card-artist').addEventListener('click',   () => openModal(r));
  card.querySelector('.card-album').addEventListener('click',    () => openModal(r));

  return card;
}

// ── Links de contacto ─────────────────────────────────────────────────────────
function buildContactLinks(r) {
  const precio     = r.precio || 0;
  const descuento  = precio ? Math.round(precio * 0.9) : 0;
  const linkML     = r.url || '';

  const ahorro = precio && descuento ? precio - descuento : 0;
  const ahorroStr = ahorro ? ` (¡Ahorrás $ ${ahorro.toLocaleString('es-AR')}!)` : '';

  const waText = [
    `Hola! Me interesa este disco:`,
    `*${r.artista} — ${r.album || r.titulo}*${r.anio ? ` (${r.anio})` : ''}`,
    precio    ? `Precio en ML: $ ${precio.toLocaleString('es-AR')}` : '',
    descuento ? `Con el 10% de descuento directo: $ ${descuento.toLocaleString('es-AR')}${ahorroStr}` : '',
    ``,
    linkML ? `Link: ${linkML}` : '',
    ``,
    `¿Está disponible?`,
    ``,
    `También podés ver todo nuestro catálogo en: https://respiraventas.github.io/vinylshop/`,
  ].filter(l => l !== undefined).join('\n');

  const mailSubject = `Consulta: ${r.artista} - ${r.album || r.titulo}`;
  const mailBody = [
    `Hola,`,
    ``,
    `Me interesa el siguiente disco:`,
    `${r.artista} — ${r.album || r.titulo}${r.anio ? ` (${r.anio})` : ''}`,
    precio ? `Precio en ML: $ ${precio.toLocaleString('es-AR')}` : '',
    ``,
    linkML ? `Link en Mercado Libre: ${linkML}` : '',
    ``,
    `¿Está disponible con el 10% de descuento por compra directa?`,
    ``,
    `Gracias!`,
  ].filter(l => l !== undefined).join('\n');

  return {
    waHref:   `https://wa.me/${WA_NUMBER}?text=${encodeURIComponent(waText)}`,
    mailHref: `mailto:${MAIL_TO}?subject=${mailSubject.replace(/&/g,'y')}&body=${mailBody.replace(/&/g,'y').replace(/\n/g,'%0A')}`,
  };
}

// ── Discos relacionados ───────────────────────────────────────────────────────
function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function getRelated(r, count = 4) {
  const artist = (r.artista || '').toLowerCase().trim();
  const genre  = (r.genero  || '').trim();

  // Nivel 1: otros discos del mismo artista (hasta 2 lugares)
  const byArtist = artist
    ? shuffle(allRecords.filter(x => x !== r && (x.artista || '').toLowerCase().trim() === artist))
    : [];

  // Nivel 2: mismo género — rellena los lugares que quedaron vacíos
  const used = new Set(byArtist.slice(0, 2));
  used.add(r);
  const byGenre = genre
    ? shuffle(allRecords.filter(x => !used.has(x) && (x.genero || '').trim() === genre))
    : [];

  const result = [
    ...byArtist.slice(0, 2),
    ...byGenre.slice(0, count - Math.min(2, byArtist.length)),
  ];

  return result.slice(0, count);
}

// ── Modal ─────────────────────────────────────────────────────────────────────
function openModal(r) {
  const gallery = document.getElementById('modal-gallery');
  if (r.imagenes?.length) {
    gallery.innerHTML = r.imagenes
      .map(s => `<img src="${esc(s)}" alt="${esc(r.titulo || '')}" loading="lazy">`)
      .join('');
  } else {
    gallery.innerHTML = `<div class="modal-gallery-placeholder">${PLACEHOLDER}</div>`;
  }

  document.getElementById('modal-artist').textContent = r.artista || '';
  document.getElementById('modal-title').textContent  = r.titulo  || '';

  const tags = [
    r.genero,
    r.origen,
    r.compania,
    r.discos   ? `${r.discos} disco${r.discos > 1 ? 's' : ''}` : null,
    r.canciones ? `${r.canciones} canciones` : null,
    r.disco     ? `Disco: ${r.disco}` : null,
    r.tapa      ? `Tapa: ${r.tapa}`   : null,
  ].filter(Boolean);
  document.getElementById('modal-tags').innerHTML =
    tags.map(t => `<span>${esc(String(t))}</span>`).join('');

  const precio    = r.precio || 0;
  const descuento = precio ? Math.round(precio * 0.9) : 0;
  document.getElementById('modal-price').textContent =
    precio ? `$ ${precio.toLocaleString('es-AR')}` : '';
  document.getElementById('modal-price-direct').textContent =
    descuento ? `→ $ ${descuento.toLocaleString('es-AR')} comprando directo` : '';

  const { waHref, mailHref } = buildContactLinks(r);
  document.getElementById('modal-btn-wa').href   = waHref;
  document.getElementById('modal-btn-mail').href = mailHref;
  document.getElementById('modal-btn-ml').href   = r.url || '#';

  // Condición Goldmine — extraer líneas tipo "Disco: VG+", "Tapa: NM", etc.
  const conditionEl = document.getElementById('modal-condition');
  const descEl      = document.getElementById('modal-desc');
  const condPattern = /^(disco|tapa|insert|vinilo|estado|funda)\s*:/i;
  const descLines   = (r.desc || '').split('\n');
  const condLines   = [];
  const restLines   = [];

  descLines.forEach(line => {
    const l = line.trim();
    if (condPattern.test(l)) {
      const colon = l.indexOf(':');
      condLines.push({ label: l.slice(0, colon).trim(), value: l.slice(colon + 1).trim() });
    } else {
      restLines.push(l);
    }
  });

  conditionEl.innerHTML = condLines.map(c => `
    <div class="condition-item">
      <span class="c-label">${esc(c.label)}</span>
      <span class="c-value">${esc(c.value)}</span>
    </div>`).join('');

  // Descripción sin las líneas de condición y sin líneas vacías iniciales
  const cleanDesc = restLines.join('\n').replace(/^\n+/, '').trim();
  descEl.textContent = cleanDesc;

  // Discos relacionados
  const relatedEl = document.getElementById('modal-related');
  const related = getRelated(r);
  if (related.length > 0) {
    relatedEl.style.display = 'block';
    relatedEl.innerHTML = `
      <p class="modal-related-title">Discos relacionados</p>
      <div class="related-grid">
        ${related.map((x, i) => {
          const src = x.imagenes?.[0];
          const imgStyle = src ? `style="background-image:url('${esc(src)}')"` : '';
          const imgClass = src ? 'related-card-img' : 'related-card-img card-placeholder';
          const price = x.precio ? `$ ${x.precio.toLocaleString('es-AR')}` : '';
          return `<div class="related-card" data-rel="${i}">
            <div class="${imgClass}" ${imgStyle}>${src ? '' : PLACEHOLDER}</div>
            <div class="related-card-info">
              <div class="related-card-artist">${esc(x.artista || '—')}</div>
              <div class="related-card-album">${esc(x.album || x.titulo || '')}</div>
              ${price ? `<div class="related-card-price">${price}</div>` : ''}
            </div>
          </div>`;
        }).join('')}
      </div>`;

    relatedEl.querySelectorAll('.related-card').forEach(el => {
      el.addEventListener('click', () => openModal(related[+el.dataset.rel]));
    });
  } else {
    relatedEl.style.display = 'none';
  }

  overlay.classList.add('open');
  document.body.style.overflow = 'hidden';
}

function closeModal() {
  overlay.classList.remove('open');
  document.body.style.overflow = '';
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function esc(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// ── Eventos ───────────────────────────────────────────────────────────────────
let searchTimer;
searchInput.addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(applyFilters, 220);
});
filterGenre.addEventListener('change',  applyFilters);
filterOrigin.addEventListener('change', applyFilters);
filterDecade.addEventListener('change', applyFilters);
filterSort.addEventListener('change',   applyFilters);
btnReset.addEventListener('click', () => {
  searchInput.value = filterGenre.value = filterOrigin.value = filterDecade.value = '';
  filterSort.value = 'new';
  applyFilters();
});
btnLoadMore.addEventListener('click', renderBatch);
modalClose.addEventListener('click', closeModal);
overlay.addEventListener('click', e => { if (e.target === overlay) closeModal(); });
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });

init();
