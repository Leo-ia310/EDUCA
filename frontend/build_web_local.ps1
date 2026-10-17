# Compila la web que sirve serve_web.js usando el backend LOCAL de backend/.env.
# Uso desde cualquier carpeta: .\frontend\build_web_local.ps1
param([string]$FlutterPath = 'C:\src\flutter\bin\flutter.bat')

$ErrorActionPreference = 'Stop'
$localConfig = @{}
Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\backend\.env') | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*?)\s*$') {
        $localConfig[$matches[1].Trim()] = $matches[2].Trim().Trim([char[]]@('"', "'"))
    }
}
if (-not $localConfig['SUPABASE_URL'] -or -not $localConfig['SUPABASE_ANON_KEY']) {
    throw 'Faltan SUPABASE_URL o SUPABASE_ANON_KEY en backend/.env.'
}
$localPort = if ($localConfig['PORT']) { [int]$localConfig['PORT'] } else { 3000 }
if ($localPort -lt 1 -or $localPort -gt 65535) { throw 'PORT inválido en backend/.env.' }
$localApiUrl = "http://localhost:$localPort/api"
$localBuildArgs = @(
    'build', 'web', '--release', '--no-pub', '--no-wasm-dry-run', '--optimization-level=2',
    '--dart-define=DEMO=false',
    "--dart-define=BACKEND_API_BASE_URL=$localApiUrl",
    ('--dart-define=SUPABASE_URL=' + $localConfig['SUPABASE_URL']),
    ('--dart-define=SUPABASE_ANON_KEY=' + $localConfig['SUPABASE_ANON_KEY'])
)
if ($localConfig['VAPID_PUBLIC_KEY']) {
    $localBuildArgs += '--dart-define=VAPID_PUBLIC_KEY=' + $localConfig['VAPID_PUBLIC_KEY']
}
Write-Output "Compilando web local conectada a $localApiUrl"
Push-Location $PSScriptRoot
try {
    & $FlutterPath @localBuildArgs 2>&1 | ForEach-Object {
        $_.ToString().Replace($localConfig['SUPABASE_ANON_KEY'], '[public-key-redacted]')
    }
    $localBuildExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $localBuildExitCode
