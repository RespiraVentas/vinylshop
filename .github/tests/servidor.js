// Servidor local mínimo para probar el sitio como si estuviera publicado.
// Sirve la raíz del repositorio imitando a GitHub Pages:
//   /                → index.html
//   /colecciones     → colecciones.html (GitHub Pages acepta la dirección sin .html)
//   lo que no existe → 404.html con código 404
// No usa ninguna librería: solo lo que trae Node.
//
// Uso: node servidor.js [puerto]   (por defecto 4173)

'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');

const RAIZ = path.resolve(__dirname, '..', '..');
const PUERTO = Number(process.argv[2] || process.env.PUERTO || 4173);

const TIPOS = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
};

function esArchivo(p) {
  try { return fs.statSync(p).isFile(); } catch { return false; }
}

// Devuelve la ruta en disco que corresponde a la dirección pedida, o null.
function resolver(pathname) {
  let rel;
  try { rel = decodeURIComponent(pathname); } catch { return null; }
  const abs = path.normalize(path.join(RAIZ, rel));
  // Nada fuera del repo, y nada de .git / .github (GitHub Pages tampoco los publica).
  if (!abs.startsWith(RAIZ)) return null;
  const relRaiz = path.relative(RAIZ, abs).split(path.sep);
  if (relRaiz[0] === '.git' || relRaiz[0] === '.github') return null;

  if (esArchivo(abs)) return abs;
  if (esArchivo(path.join(abs, 'index.html'))) return path.join(abs, 'index.html');
  if (esArchivo(abs + '.html')) return abs + '.html';
  return null;
}

const servidor = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  let archivo = resolver(url.pathname);
  let codigo = 200;
  if (!archivo) {
    archivo = path.join(RAIZ, '404.html');
    codigo = 404;
  }
  const tipo = TIPOS[path.extname(archivo).toLowerCase()] || 'application/octet-stream';
  res.writeHead(codigo, { 'Content-Type': tipo, 'Cache-Control': 'no-cache' });
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(archivo).pipe(res);
});

servidor.listen(PUERTO, '127.0.0.1', () => {
  console.log(`Sitio servido en http://127.0.0.1:${PUERTO} (raíz: ${RAIZ})`);
});
