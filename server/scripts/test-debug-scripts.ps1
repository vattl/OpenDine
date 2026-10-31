$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "debug-env-common.ps1")

function Assert-Throws([scriptblock]$Action, [string]$Message) {
    try {
        & $Action
    } catch {
        return
    }
    throw $Message
}

Assert-DebugDatabaseUrl "jdbc:mysql://127.0.0.1:3307/db_diancan_debug?useSSL=false"
Assert-Throws {
    Assert-DebugDatabaseUrl "jdbc:mysql://127.0.0.1:3306/db_diancan?useSSL=false"
} "Production schema URL should have been rejected"
Assert-Throws {
    Assert-DebugDatabaseUrl "jdbc:mysql://127.0.0.1:3306/db_diancan_debug?useSSL=false"
} "The production MySQL port should have been rejected"
Assert-Throws {
    Assert-DebugDatabaseUrl "jdbc:mysql://127.0.0.1:3306/db_diancan_debug_backup"
} "A similarly named schema should have been rejected"

Assert-DebugDatabaseGrants "GRANT ALL PRIVILEGES ON ``db_diancan_debug``.* TO ``diancan_debug``@``localhost``"
Assert-Throws {
    Assert-DebugDatabaseGrants "GRANT ALL PRIVILEGES ON ``db_diancan``.* TO ``diancan_debug``@``localhost``"
} "Production schema grant should have been rejected"
Assert-Throws {
    Assert-DebugDatabaseGrants "GRANT USAGE ON *.* TO ``diancan_debug``@``localhost``"
} "Missing debug schema grant should have been rejected"

$repoRoot = Get-DebugRepoRoot
$setupScript = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "scripts\setup-debug.ps1")
if (-not ($setupScript -match "AuditSchemaMigration")) {
    throw "Debug setup must run the explicit V007 migration."
}
foreach ($migration in @("db_migration_printing.sql", "db_migration_printing_template.sql", "db_migration_printing_job_biz_trace.sql")) {
    if (-not ($setupScript -match [regex]::Escape($migration))) {
        throw "Debug setup must include $migration."
    }
}
if (-not (Test-DebugApplicationCommandLine `
        "java -cp $repoRoot\target\classes com.lanf.Application" $repoRoot)) {
    throw "The debug application command line should have been recognized"
}
if (Test-DebugApplicationCommandLine `
        "java -jar C:\other\application.jar" $repoRoot) {
    throw "An unrelated Java command line should not have been recognized"
}

$tempEnv = New-TemporaryFile
try {
    Set-Content -LiteralPath $tempEnv.FullName -Encoding UTF8 -Value @(
        "# comment",
        "DEBUG_TEST_SIMPLE=value",
        "DEBUG_TEST_EQUALS=left=right",
        "",
        "DEBUG_TEST_SPACED = trimmed"
    )
    Import-DebugEnv $tempEnv.FullName
    if ($env:DEBUG_TEST_SIMPLE -ne "value") { throw "Simple environment value was not loaded" }
    if ($env:DEBUG_TEST_EQUALS -ne "left=right") { throw "Value containing '=' was not preserved" }
    if ($env:DEBUG_TEST_SPACED -ne "trimmed") { throw "Environment key/value was not trimmed" }
} finally {
    Remove-Item -LiteralPath $tempEnv.FullName -Force -ErrorAction SilentlyContinue
    Remove-Item Env:DEBUG_TEST_SIMPLE,Env:DEBUG_TEST_EQUALS,Env:DEBUG_TEST_SPACED -ErrorAction SilentlyContinue
}

Write-Host "Debug script tests passed." -ForegroundColor Green
