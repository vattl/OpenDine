$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "debug-env-common.ps1")

$repoRoot = Get-DebugRepoRoot
$rootPasswordFile = Join-Path $repoRoot ".local\mysql-debug\root-password"
if (-not (Get-NetTCPConnection -State Listen -LocalPort 3307 -ErrorAction SilentlyContinue)) {
    Write-Host "Independent debug MySQL is already stopped."
    exit 0
}
if (-not (Test-Path -LiteralPath $rootPasswordFile -PathType Leaf)) {
    throw "Debug MySQL root credential file is missing; refusing to force-stop the server."
}

$previousPassword = $env:MYSQL_PWD
try {
    $env:MYSQL_PWD = (Get-Content -Raw -LiteralPath $rootPasswordFile).Trim()
    $mysqladmin = Join-Path (Split-Path -Parent (Get-MySqlCommand)) "mysqladmin.exe"
    & $mysqladmin --protocol=tcp --host=127.0.0.1 --port=3307 --user=root shutdown
    if ($LASTEXITCODE -ne 0) { throw "Could not stop independent debug MySQL cleanly." }
} finally {
    $env:MYSQL_PWD = $previousPassword
}
Write-Host "Independent debug MySQL stopped." -ForegroundColor Green
