# -----------------------------------------------------------------------------
# Educa360 — arrancar la app en desarrollo con las credenciales de Supabase.
#
# Uso:
#   .\run_dev.ps1              # ejecuta en el device por defecto
#   .\run_dev.ps1 -Device windows
#   .\run_dev.ps1 -Device chrome
#
# Este script lee `.env` y arma los `--dart-define` que la app espera.
# -----------------------------------------------------------------------------

param(
    [string]$Device = ""
)

if (-not (Test-Path ".env")) {
    Write-Error "Falta .env en la raíz. Copia .env.example y complétalo."
    exit 1
}

# Cargar .env como variables locales.
$env_vars = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match "^\s*([^#=]+?)\s*=\s*(.+?)\s*$") {
        $env_vars[$matches[1]] = $matches[2]
    }
}

$url = $env_vars["SUPABASE_URL"]
$key = $env_vars["SUPABASE_ANON_KEY"]
$vapidKey = $env_vars["VAPID_PUBLIC_KEY"]

if (-not $url -or -not $key) {
    Write-Error "SUPABASE_URL o SUPABASE_ANON_KEY vacíos en .env"
    exit 1
}

$flutterArgs = @(
    "run",
    "--dart-define=SUPABASE_URL=$url",
    "--dart-define=SUPABASE_ANON_KEY=$key"
)

if ($vapidKey) {
    $flutterArgs += "--dart-define=VAPID_PUBLIC_KEY=$vapidKey"
}

if ($Device) {
    $flutterArgs += "-d"
    $flutterArgs += $Device
}

Write-Host "Arrancando Educa360 conectado a $url" -ForegroundColor Green
& flutter @flutterArgs
