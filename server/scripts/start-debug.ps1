param(
    [switch]$SkipDatabaseCheck,
    [string]$EnvFile
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "debug-env-common.ps1")

$repoRoot = Get-DebugRepoRoot
$resolvedEnvFile = if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    Join-Path $repoRoot ".env.debug"
} else {
    [IO.Path]::GetFullPath($EnvFile)
}
Import-DebugEnv $resolvedEnvFile
Assert-DebugDatabaseUrl $env:DEBUG_DB_URL

$listener = Get-NetTCPConnection -State Listen -LocalPort 18080 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
    if (Test-DebugApplicationCommandLine $process.CommandLine $repoRoot) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:18080/kds-demo.html" -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Host "Debug server is already running at http://127.0.0.1:18080 (PID $($listener.OwningProcess))." -ForegroundColor Green
                exit 0
            }
        } catch {
            throw "Port 18080 belongs to this project, but its health check failed. Stop PID $($listener.OwningProcess) and retry."
        }
    }
    throw "Port 18080 is occupied by $($process.Name) (PID $($listener.OwningProcess)), not by this debug server."
}

Start-DebugMySql
& (Join-Path $PSScriptRoot "check-debug-env.ps1") `
        -SkipDatabase:$SkipDatabaseCheck -EnvFile $resolvedEnvFile

$env:SPRING_APPLICATION_JSON = $null
$env:SPRING_CONFIG_LOCATION = $null
$env:SPRING_PROFILES_ACTIVE = "debug"
$env:SPRING_DATASOURCE_URL = $env:DEBUG_DB_URL
$env:SPRING_DATASOURCE_USERNAME = $env:DEBUG_DB_USERNAME
$env:SPRING_DATASOURCE_PASSWORD = $env:DEBUG_DB_PASSWORD
$env:SERVER_ADDRESS = "127.0.0.1"
$env:SERVER_PORT = "18080"
$env:APP_SCHEDULING_ENABLED = "false"
$env:ZSQ_AUTO_API_ENABLED = "false"
$env:ZSQ_TAKEOUT_SYNC_ENABLED = "false"
Write-Host "Starting debug server at http://127.0.0.1:18080 ..." -ForegroundColor Cyan

Push-Location $repoRoot
try {
    & (Join-Path $repoRoot "mvnw.cmd") "spring-boot:run" "-Dspring-boot.run.profiles=debug"
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
