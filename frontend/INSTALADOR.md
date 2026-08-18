# 🚀 INSTALADOR — Educa360

Guía paso a paso para correr el proyecto **desde cero** en Windows.  
Tiempo estimado: ~15 minutos (sin contar descargas).

---

## ✅ Requisitos previos

| Herramienta | Versión mínima | Para qué sirve |
|-------------|---------------|----------------|
| Windows | 10 u 11 (64-bit) | Sistema operativo |
| Git | cualquiera | Clonar el repositorio |
| Flutter SDK | 3.24+ | Compilar y correr la app |
| Chrome | cualquiera | Ver la app en web |
| VS Code *(opcional)* | cualquiera | Editor recomendado |

---

## PASO 1 — Instalar Git

1. Ir a: https://git-scm.com/download/win
2. Descargar el instalador y ejecutarlo con todas las opciones por defecto.
3. Verificar que quedó instalado:
   ```powershell
   git --version
   # Debe mostrar algo como: git version 2.x.x
   ```

---

## PASO 2 — Instalar Flutter

1. Ir a: https://docs.flutter.dev/get-started/install/windows/web
2. Descargar el archivo `.zip` de Flutter SDK.
3. Descomprimir en `C:\src\flutter` (crear la carpeta si no existe).
   > ⚠️ **NO** pongas Flutter en `C:\Program Files\` ni en carpetas con espacios.
4. Agregar Flutter al PATH del sistema para poder usar el comando `flutter` desde cualquier terminal:

   - Abrir **PowerShell** y ejecutar este comando (solo una vez):
     ```powershell
     [System.Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\src\flutter\bin", "User")
     ```
   - Cerrar y volver a abrir PowerShell.

5. Verificar la instalación:
   ```powershell
   flutter doctor
   ```
   Debe mostrar algo como:
   ```
   [✓] Flutter (Channel stable, 3.x.x)
   [✓] Chrome - develop for the web
   ```
   > Es normal que aparezcan advertencias de Android Studio o Xcode si no los tienes instalados. Para correr en web **no los necesitas**.

6. Habilitar soporte web (ejecutar una sola vez):
   ```powershell
   flutter config --enable-web
   ```

---

## PASO 3 — Clonar el repositorio

Abre PowerShell en la carpeta donde quieras guardar el proyecto y ejecuta:

```powershell
git clone <URL_DEL_REPOSITORIO>
cd EDUCA\frontend
```

> 💡 Pídele la URL del repositorio al dueño del proyecto si no la tienes.
> ⚠️ La app Flutter vive en la carpeta `frontend/` del repo (el backend de
> Supabase está en `backend/`, aparte). Todos los comandos de esta guía se
> ejecutan **dentro de `frontend/`**.

---

## PASO 4 — Configurar las variables de entorno

El proyecto necesita conectarse a Supabase. Las credenciales se guardan en un archivo `.env`.

1. Dentro de la carpeta del proyecto, copia el archivo de ejemplo:
   ```powershell
   Copy-Item .env.example .env
   ```

2. Abre el archivo `.env` con cualquier editor de texto (Bloc de Notas, VS Code, etc.) y rellena los valores reales:
   ```
   SUPABASE_URL=https://tu-proyecto.supabase.co
   SUPABASE_ANON_KEY=sb_publishable_...
   SUPABASE_PROJECT_REF=tu-proyecto
   ```
   > 💡 Pídele estos valores al dueño del proyecto. Están en el panel de Supabase en:  
   > **Project Settings → API → Project URL y anon public key**

---

## PASO 5 — Instalar dependencias del proyecto

Desde la carpeta del proyecto:

```powershell
flutter pub get
```

Esto descargará todos los paquetes necesarios. Solo tienes que hacerlo **una vez** (o cuando cambien los paquetes).

---

## PASO 6 — Correr el proyecto en Chrome 🌐

Usa el script incluido en el proyecto:

```powershell
.\run_dev.ps1 -Device chrome
```

O el comando completo si prefieres:

```powershell
flutter run -d chrome --dart-define=SUPABASE_URL=https://tu-proyecto.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
```

Chrome se abrirá automáticamente con la app.

> 🕐 La primera vez puede tardar 1-2 minutos en compilar. Las siguientes veces es mucho más rápido.

---

## Comandos útiles mientras corre la app

Una vez la app está corriendo, desde la misma terminal puedes presionar:

| Tecla | Acción |
|-------|--------|
| `r` | **Hot reload** — aplica cambios de código al instante sin reiniciar |
| `R` | **Hot restart** — reinicia la app completa |
| `q` | **Salir** — cierra la app y la terminal |
| `d` | **Detach** — deja la app corriendo y libera la terminal |

---

## Solución de problemas comunes

### ❌ `flutter` no se reconoce como comando
**Causa:** Flutter no está en el PATH.  
**Solución:** Ejecuta el comando del Paso 2.4 y **cierra y reabre** la terminal.

---

### ❌ Error: `SUPABASE_URL o SUPABASE_ANON_KEY vacíos`
**Causa:** Falta el archivo `.env` o tiene los valores vacíos.  
**Solución:** Repite el Paso 4.

---

### ❌ Error al compilar / dependencias rotas
**Solución:** Ejecuta estos comandos en orden:
```powershell
flutter clean
flutter pub get
flutter run -d chrome ...
```

---

### ❌ Chrome no se abre o aparece en blanco
**Solución:** Espera unos segundos, a veces el servidor web tarda un momento. Si persiste:
```powershell
flutter run -d chrome --web-port=8080 ...
```
Y abre manualmente `http://localhost:8080` en Chrome.

---

## Estructura del proyecto (referencia rápida)

```
EDUCA/
├── frontend/            # App Flutter (esta carpeta)
│   ├── lib/
│   │   ├── core/          # Tema, rutas, constantes globales
│   │   ├── features/      # Módulos: auth, dashboard, asistencia, etc.
│   │   └── shared/        # Modelos y widgets reutilizables
│   ├── assets/            # Imágenes e iconos
│   ├── web/               # Configuración web (index.html, manifest)
│   ├── .env               # ⚠️ Credenciales (NO subir a Git)
│   ├── .env.example       # Plantilla del .env
│   ├── run_dev.ps1        # Script para arrancar fácilmente
│   └── pubspec.yaml       # Dependencias del proyecto
└── backend/
    └── migrations/         # Scripts SQL de la base de datos
```

---

## Resumen rápido (para la próxima vez)

Una vez configurado todo, para correr el proyecto solo necesitas:

```powershell
# 1. Ir a la carpeta de la app
cd "C:\ruta\al\proyecto\EDUCA\frontend"

# 2. Arrancar
.\run_dev.ps1 -Device chrome
```

¡Listo! 🎉
