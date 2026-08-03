// Servidor estático mínimo para el build de Flutter web (build/web).
// Fuerza los MIME correctos (Windows a veces sirve .js como text/plain, lo que
// hace que el navegador se niegue a ejecutar main.dart.js) y hace fallback SPA
// a index.html para las rutas de go_router.
//
// Uso:  node serve_web.js [puerto]
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, 'build', 'web');
const PORT = parseInt(process.argv[2] || '8080', 10);
const HOST = '127.0.0.1';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json; charset=utf-8',
  '.bin': 'application/octet-stream',
};

function send(res, status, body, headers) {
  res.writeHead(status, headers || {});
  res.end(body);
}

const server = http.createServer((req, res) => {
  try {
    let urlPath = decodeURIComponent(req.url.split('?')[0]);
    if (urlPath === '/') urlPath = '/index.html';

    let filePath = path.join(ROOT, path.normalize(urlPath));
    // Evitar path traversal fuera de ROOT.
    if (!filePath.startsWith(ROOT)) return send(res, 403, 'Forbidden');

    fs.stat(filePath, (err, stat) => {
      if (err || !stat.isFile()) {
        // Fallback SPA: cualquier ruta desconocida -> index.html.
        filePath = path.join(ROOT, 'index.html');
      }
      const ext = path.extname(filePath).toLowerCase();
      const type = MIME[ext] || 'application/octet-stream';
      fs.readFile(filePath, (e, data) => {
        if (e) return send(res, 500, 'Internal Server Error');
        send(res, 200, data, {
          'Content-Type': type,
          'Cache-Control': 'no-cache',
        });
      });
    });
  } catch (_) {
    send(res, 500, 'Internal Server Error');
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Educa360 (release) sirviendo en http://${HOST}:${PORT}`);
  console.log(`Root: ${ROOT}`);
});
