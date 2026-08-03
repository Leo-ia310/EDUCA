# -----------------------------------------------------------------------------
# Educa360 — arrancar la app en MODO DEMO (datos mock, sin backend).
#
# Uso:
#   .\run_demo.ps1              # device por defecto
#   .\run_demo.ps1 -Device chrome
#
# La app funciona al 100% con datos de demostración. No necesita Supabase.
# Login demo:
#   Código de colegio: EDU360
#   Contraseña:        demo1234
#   Usuario (prefijo): student@  |  teacher@  |  parent@  |  admin@
# -----------------------------------------------------------------------------

param(
    [string]$Device = ""
)

$flutterArgs = @(
    "run",
    "--dart-define=DEMO=true"
)

if ($Device) {
    $flutterArgs += "-d"
    $flutterArgs += $Device
}

Write-Host "Arrancando Educa360 en MODO DEMO (datos mock)" -ForegroundColor Green
Write-Host "Login: colegio EDU360 / pass demo1234 / usuario student@ (o teacher@, parent@, admin@)" -ForegroundColor Cyan
& flutter @flutterArgs
