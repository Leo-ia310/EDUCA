# -----------------------------------------------------------------------------
# Educa360 — arrancar la app en desarrollo con las credenciales de Supabase.
#
# Uso:
#   .\run_dev.ps1              # ejecuta en el device por defecto
#   .\run_dev.ps1 -Device windows
#   .\run_dev.ps1 -Device chrome
#
# Lee las credenciales centralizadas en `backend/.env` (copia de backend/.env.example)
# y arma los `--dart-define` que la app espera. Las claves viven en el backend;
# el frontend solo las recibe en tiempo de build.
# -----------------------------------------------------------------------------

param(
    [string]$Device = ""
)

# Credenciales centralizadas en el backend. Fallback a un .env local del frontend.
$envPath = "../backend/.env"
if (-not (Test-Path $envPath)) {
    if (Test-Path ".env") {
        $envPath = ".env"
    } else {
        Write-Error "Falta backend/.env. Copia backend/.env.example a backend/.env y complétalo."
        exit 1
    }
}

# Cargar .env como variables locales.
$env_vars = @{}
Get-Content $envPath | ForEach-Object {
    if ($_ -match "^\s*([^#=]+?)\s*=\s*(.+?)\s*$") {
        $env_vars[$matches[1]] = $matches[2]
    }
}

$url = $env_vars["SUPABASE_URL"]
$key = $env_vars["SUPABASE_ANON_KEY"]
$vapidKey = $env_vars["VAPID_PUBLIC_KEY"]
$backendApiBaseUrl = $env_vars["BACKEND_API_BASE_URL"]
if (-not $backendApiBaseUrl) {
    $backendApiBaseUrl = "http://localhost:3000/api"
}

if (-not $url -or -not $key) {
    Write-Error "SUPABASE_URL o SUPABASE_ANON_KEY vacíos en .env"
    exit 1
}

$flutterArgs = @(
    "run",
    "--dart-define=SUPABASE_URL=$url",
    "--dart-define=SUPABASE_ANON_KEY=$key",
    "--dart-define=BACKEND_API_BASE_URL=$backendApiBaseUrl"
)

if ($vapidKey) {
    $flutterArgs += "--dart-define=VAPID_PUBLIC_KEY=$vapidKey"
}

if ($Device) {
    $flutterArgs += "-d"
    $flutterArgs += $Device
}

Write-Host "Arrancando Educa360 conectado a $url y backend $backendApiBaseUrl" -ForegroundColor Green
& flutter @flutterArgs
