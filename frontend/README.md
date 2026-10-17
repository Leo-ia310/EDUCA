# Nivra — Flutter

La URL del backend se incorpora al compilar con `BACKEND_API_BASE_URL`.
Levantar otro backend después no cambia la URL de una web o un APK ya compilados.

## Web con backend local

1. Inicia `npm run dev` en `backend/`.
2. Desde `frontend/`, ejecuta `./run_dev.ps1 -Device web-server` para desarrollo,
   o `./build_web_local.ps1` si usas el servidor estático `node serve_web.js 8080`.
3. Recarga el navegador después de recompilar la web estática.

`build_web_local.ps1` lee `PORT` y las claves públicas de `backend/.env`;
con `PORT=3001` la API queda en `http://localhost:3001/api`.
No incluye claves privadas ni activa el modo demo.

En `backend/.env`, permite ambos orígenes locales con:

```dotenv
CORS_ORIGIN=http://127.0.0.1:8080,http://localhost:8080
```

Un APK para usar en un teléfono debe compilarse con la URL HTTPS pública
del backend. `build_web_local.ps1` prepara exclusivamente la web local.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
