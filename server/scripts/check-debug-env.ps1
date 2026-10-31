param(
    [switch]$SkipDatabase,
    [string]$EnvFile
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "debug-env-common.ps1")

$repoRoot = Get-DebugRepoRoot
$envFile = if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    Join-Path $repoRoot ".env.debug"
} else {
    [IO.Path]::GetFullPath($EnvFile)
}
Import-DebugEnv $envFile
Assert-DebugDatabaseUrl $env:DEBUG_DB_URL

if ($env:DEBUG_DB_USERNAME -ne "diancan_debug") {
    throw "Safety check failed: DEBUG_DB_USERNAME must be diancan_debug."
}
if ([string]::IsNullOrWhiteSpace($env:DEBUG_DB_PASSWORD)) {
    throw "DEBUG_DB_PASSWORD is empty. Run setup-debug.ps1 again."
}
if ([string]::IsNullOrWhiteSpace($env:AUTH_JWT_CURRENT_SECRET) -or $env:AUTH_JWT_CURRENT_SECRET.Length -lt 32) {
    throw "AUTH_JWT_CURRENT_SECRET must contain at least 32 characters. Run setup-debug.ps1 again."
}

$dataDir = if ([IO.Path]::IsPathRooted($env:DEBUG_DATA_DIR)) {
    $env:DEBUG_DATA_DIR
} else {
    Join-Path $repoRoot $env:DEBUG_DATA_DIR
}
if (-not (Test-Path -LiteralPath $dataDir -PathType Container)) {
    throw "Debug data directory does not exist: $dataDir"
}

if (-not $SkipDatabase) {
    Start-DebugMySql
    $schemaCount = Invoke-MySql $env:DEBUG_DB_USERNAME $env:DEBUG_DB_PASSWORD `
            "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='db_diancan_debug';"
    if ([int]($schemaCount | Select-Object -Last 1) -ne 1) {
        throw "Debug database db_diancan_debug does not exist."
    }

    $grants = (Invoke-MySql $env:DEBUG_DB_USERNAME $env:DEBUG_DB_PASSWORD "SHOW GRANTS;") -join "`n"
    Assert-DebugDatabaseGrants $grants
}

Write-Host "Debug environment checks passed." -ForegroundColor Green
Write-Host "Profile: debug | URL: http://127.0.0.1:18080 | Schema: db_diancan_debug"
