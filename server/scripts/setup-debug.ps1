param(
    [switch]$ResetDatabase,
    [switch]$Force,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "debug-env-common.ps1")

$repoRoot = Get-DebugRepoRoot
$envFile = Join-Path $repoRoot ".env.debug"
$runtimeDir = Join-Path $repoRoot ".local\mysql-debug"
$dataDir = Join-Path $runtimeDir "data"
$configFile = Join-Path $runtimeDir "my.ini"
$rootPasswordFile = Join-Path $runtimeDir "root-password"
$uploadDir = Join-Path $repoRoot ".local\debug"
$databaseName = "db_diancan_debug"
$databaseUser = "diancan_debug"
$schemaFile = Join-Path $repoRoot "docs\db_diancan.sql"
$migrationFiles = @(
    (Join-Path $repoRoot "docs\db_migration_kds.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_merge_meituan.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_skewer_gate.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_auto_off_order.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_flow_batch.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_serve_print_enabled.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_ticket_dish_flags.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_ticket_served_quantity.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_ticket_prep_cooked_quantity.sql"),
    (Join-Path $repoRoot "docs\db_migration_cashier_kds_delivery.sql"),
    (Join-Path $repoRoot "docs\db_migration_cashier_cloud_first_kds.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_cashier_replication.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_authority_v2.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_v2_command_ledger.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_v2_event_log.sql"),
    (Join-Path $repoRoot "docs\db_migration_kds_shared_revision.sql"),
    (Join-Path $repoRoot "docs\db_migration_payment_module.sql"),
    (Join-Path $repoRoot "docs\db_migration_payment_ninefold_config.sql"),
    (Join-Path $repoRoot "docs\db_migration_wechat_prepay_ninefold_eligible_dining_types.sql"),
    (Join-Path $repoRoot "docs\db_migration_payment_platform_pub_key_ref.sql"),
    (Join-Path $repoRoot "docs\db_migration_payment_client_channels.sql"),
    (Join-Path $repoRoot "docs\db_migration_unified_payment_channels.sql"),
    (Join-Path $repoRoot "docs\db_migration_payment_refund_idempotency.sql"),
    (Join-Path $repoRoot "docs\db_migration_cashier_collection_intent.sql"),
    (Join-Path $repoRoot "docs\db_migration_printing.sql"),
    (Join-Path $repoRoot "docs\db_migration_printing_template.sql"),
    (Join-Path $repoRoot "docs\db_migration_printing_job_biz_trace.sql"),
    (Join-Path $repoRoot "docs\db_migration_stock_prep_bom_plan_config.sql"),
    (Join-Path $repoRoot "docs\db_migration_shop_ordering_flags.sql"),
    (Join-Path $repoRoot "docs\db_migration_admin_token_version.sql")
)

foreach ($path in @($schemaFile) + $migrationFiles + @(Join-Path $repoRoot "mvnw.cmd")) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}
$mysqld = Get-MySqlServerCommand
$mysql = Get-MySqlCommand
$mysqlBaseDir = Split-Path -Parent (Split-Path -Parent $mysqld)

New-Item -ItemType Directory -Force -Path $runtimeDir,$dataDir | Out-Null
$basePath = $mysqlBaseDir -replace '\\', '/'
$dataPath = $dataDir -replace '\\', '/'
$runtimePath = $runtimeDir -replace '\\', '/'
$configLines = @(
    "[mysqld]",
    "basedir=`"$basePath`"",
    "datadir=`"$dataPath`"",
    "port=3307",
    "bind-address=127.0.0.1",
    "mysqlx=0",
    "character-set-server=utf8mb4",
    "collation-server=utf8mb4_0900_ai_ci",
    "pid-file=`"$runtimePath/mysqld.pid`"",
    "log-error=`"$runtimePath/mysqld-error.log`"",
    "[client]",
    "host=127.0.0.1",
    "port=3307",
    "default-character-set=utf8mb4"
)
[IO.File]::WriteAllLines($configFile, $configLines, (New-Object Text.UTF8Encoding($false)))

function Protect-LocalSecret([string]$Path) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetOwner($identity.User)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($identity.User, (New-Object Security.Principal.SecurityIdentifier("S-1-5-18")))) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, "FullControl", "Allow")))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

$isInitialized = Test-Path -LiteralPath (Join-Path $dataDir "mysql") -PathType Container
if (-not $isInitialized) {
    if ((Get-ChildItem -LiteralPath $dataDir -Force | Measure-Object).Count -gt 0) {
        throw "Debug MySQL data directory is non-empty but not initialized: $dataDir"
    }
    Write-Host "Initializing independent MySQL data directory on port 3307 ..." -ForegroundColor Cyan
    & $mysqld ('--defaults-file=' + $configFile) --initialize-insecure --console
    if ($LASTEXITCODE -ne 0) { throw "Initializing independent debug MySQL failed." }
    $rootPassword = New-DebugDatabasePassword
    [IO.File]::WriteAllText($rootPasswordFile, $rootPassword, (New-Object Text.UTF8Encoding($false)))
    Protect-LocalSecret $rootPasswordFile
} else {
    if (-not (Test-Path -LiteralPath $rootPasswordFile -PathType Leaf)) {
        throw "Debug MySQL root credential file is missing; refusing an unsafe recovery."
    }
    $rootPassword = (Get-Content -Raw -LiteralPath $rootPasswordFile).Trim()
}

Start-DebugMySql

if (Test-Path -LiteralPath $envFile -PathType Leaf) {
    Import-DebugEnv $envFile
    $databasePassword = $env:DEBUG_DB_PASSWORD
} else {
    $databasePassword = New-DebugDatabasePassword
}
if ([string]::IsNullOrWhiteSpace($databasePassword)) { $databasePassword = New-DebugDatabasePassword }

if (-not $isInitialized) {
    Invoke-MySql root "" @"
ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootPassword';
CREATE DATABASE IF NOT EXISTS ``$databaseName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS '$databaseUser'@'localhost' IDENTIFIED BY '$databasePassword';
CREATE USER IF NOT EXISTS '$databaseUser'@'127.0.0.1' IDENTIFIED BY '$databasePassword';
"@ | Out-Null
}

if ($ResetDatabase -and -not $Force) {
    $confirmation = Read-Host "Type db_diancan_debug to permanently reset the debug database"
    if ($confirmation -cne $databaseName) { throw "Database reset cancelled." }
}
if ($ResetDatabase) {
    Invoke-MySql root $rootPassword "DROP DATABASE IF EXISTS ``$databaseName``;" | Out-Null
}

Invoke-MySql root $rootPassword @"
CREATE DATABASE IF NOT EXISTS ``$databaseName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS '$databaseUser'@'localhost' IDENTIFIED BY '$databasePassword';
CREATE USER IF NOT EXISTS '$databaseUser'@'127.0.0.1' IDENTIFIED BY '$databasePassword';
ALTER USER '$databaseUser'@'localhost' IDENTIFIED BY '$databasePassword';
ALTER USER '$databaseUser'@'127.0.0.1' IDENTIFIED BY '$databasePassword';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '$databaseUser'@'localhost';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '$databaseUser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON ``$databaseName``.* TO '$databaseUser'@'localhost';
GRANT ALL PRIVILEGES ON ``$databaseName``.* TO '$databaseUser'@'127.0.0.1';
FLUSH PRIVILEGES;
"@ | Out-Null

function Import-DebugSqlFile([string]$Path) {
    $previousPassword = $env:MYSQL_PWD
    try {
        $env:MYSQL_PWD = $databasePassword
        $sourcePath = $Path -replace '\\', '/'
        & $mysql --protocol=tcp --host=127.0.0.1 --port=3307 --user=$databaseUser --database=$databaseName `
                --default-character-set=utf8mb4 --execute="source $sourcePath"
        if ($LASTEXITCODE -ne 0) { throw "Importing $Path failed." }
    } finally {
        $env:MYSQL_PWD = $previousPassword
    }
}

$tableCount = [int]((Invoke-MySql $databaseUser $databasePassword `
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$databaseName';") | Select-Object -Last 1)
if ($tableCount -eq 0) {
    Import-DebugSqlFile $schemaFile
    Write-Host "Imported database baseline." -ForegroundColor Green
} else {
    Write-Host "Keeping $tableCount existing debug tables." -ForegroundColor Yellow
}
Invoke-MySql $databaseUser $databasePassword @"
CREATE TABLE IF NOT EXISTS ``$databaseName``.``_debug_schema_migration`` (
  ``filename`` varchar(255) NOT NULL,
  ``status`` varchar(16) NOT NULL,
  ``applied_at`` datetime NULL,
  PRIMARY KEY (``filename``)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"@ | Out-Null

foreach ($migrationFile in $migrationFiles) {
    $migrationName = [IO.Path]::GetFileName($migrationFile)
    $status = (Invoke-MySql $databaseUser $databasePassword `
            "SELECT status FROM ``$databaseName``.``_debug_schema_migration`` WHERE filename='$migrationName';") | Select-Object -Last 1
    if ($status -eq "applied") { continue }
    if ($status) {
        throw "Migration $migrationName previously stopped with status '$status'. Run setup-debug.ps1 -ResetDatabase."
    }
    Invoke-MySql $databaseUser $databasePassword `
            "INSERT INTO ``$databaseName``.``_debug_schema_migration`` (filename,status) VALUES ('$migrationName','started');" | Out-Null
    try {
        Import-DebugSqlFile $migrationFile
        Invoke-MySql $databaseUser $databasePassword `
                "UPDATE ``$databaseName``.``_debug_schema_migration`` SET status='applied',applied_at=NOW() WHERE filename='$migrationName';" | Out-Null
    } catch {
        Invoke-MySql $databaseUser $databasePassword `
                "UPDATE ``$databaseName``.``_debug_schema_migration`` SET status='failed' WHERE filename='$migrationName';" | Out-Null
        throw
    }
}

foreach ($name in @("qrcode", "dish", "avatar", "advertising", "images", "offline-collect", "payment-keys")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $uploadDir "uploads\$name") | Out-Null
}

$managedValues = [ordered]@{
    DEBUG_DB_URL = "jdbc:mysql://127.0.0.1:3307/$databaseName`?serverTimezone=Asia/Shanghai&useUnicode=true&characterEncoding=utf8&allowPublicKeyRetrieval=true&useSSL=false"
    DEBUG_DB_USERNAME = $databaseUser
    DEBUG_DB_PASSWORD = $databasePassword
    DEBUG_DATA_DIR = ($uploadDir -replace '\\', '/')
    AUTH_JWT_CURRENT_SECRET = if ([string]::IsNullOrWhiteSpace($env:AUTH_JWT_CURRENT_SECRET)) { New-DebugDatabasePassword } else { $env:AUTH_JWT_CURRENT_SECRET }
    AUTH_JWT_PREVIOUS_SECRET = if ($null -eq $env:AUTH_JWT_PREVIOUS_SECRET) { "" } else { $env:AUTH_JWT_PREVIOUS_SECRET }
}
$preservedLines = @()
if (Test-Path -LiteralPath $envFile -PathType Leaf) {
    $preservedLines = Get-Content -LiteralPath $envFile -Encoding UTF8 | Where-Object {
        $line = $_.Trim(); $separator = $line.IndexOf("=")
        if ($separator -lt 1) { return $true }
        return -not $managedValues.Contains($line.Substring(0, $separator).Trim())
    }
}
$envLines = @($managedValues.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })
if ($preservedLines.Count -gt 0) { $envLines += ""; $envLines += $preservedLines }
[IO.File]::WriteAllLines($envFile, $envLines, (New-Object Text.UTF8Encoding($false)))
Protect-LocalSecret $envFile

$migrationJar = Join-Path $repoRoot "target\diancan-0.0.1-SNAPSHOT.jar"
if (-not $SkipBuild) {
    Push-Location $repoRoot
    try {
        & (Join-Path $repoRoot "mvnw.cmd") -DskipTests package
        if ($LASTEXITCODE -ne 0) { throw "Maven package failed." }
    } finally { Pop-Location }
}
if (-not (Test-Path -LiteralPath $migrationJar -PathType Leaf)) {
    throw "C007 V007 debug migration requires $migrationJar. Re-run without -SkipBuild."
}

# V007 remains an explicit migration. This setup path targets only the
# isolated db_diancan_debug instance and never runs with production settings.
$hadMigrationUrl = Test-Path Env:MIGRATION_JDBC_URL
$hadMigrationUser = Test-Path Env:MIGRATION_DB_USER
$hadMigrationPassword = Test-Path Env:MIGRATION_DB_PASSWORD
$previousMigrationUrl = $env:MIGRATION_JDBC_URL
$previousMigrationUser = $env:MIGRATION_DB_USER
$previousMigrationPassword = $env:MIGRATION_DB_PASSWORD
$env:MIGRATION_JDBC_URL = $env:DEBUG_DB_URL
$env:MIGRATION_DB_USER = $env:DEBUG_DB_USERNAME
$env:MIGRATION_DB_PASSWORD = $env:DEBUG_DB_PASSWORD
Push-Location $repoRoot
try {
    & java "-Dloader.main=com.lanf.database.AuditSchemaMigration" `
            -cp $migrationJar `
            org.springframework.boot.loader.PropertiesLauncher
    if ($LASTEXITCODE -ne 0) { throw "C007 V007 debug migration failed." }
} finally {
    if ($hadMigrationUrl) { $env:MIGRATION_JDBC_URL = $previousMigrationUrl } else { Remove-Item Env:MIGRATION_JDBC_URL -ErrorAction SilentlyContinue }
    if ($hadMigrationUser) { $env:MIGRATION_DB_USER = $previousMigrationUser } else { Remove-Item Env:MIGRATION_DB_USER -ErrorAction SilentlyContinue }
    if ($hadMigrationPassword) { $env:MIGRATION_DB_PASSWORD = $previousMigrationPassword } else { Remove-Item Env:MIGRATION_DB_PASSWORD -ErrorAction SilentlyContinue }
    Pop-Location
}

& (Join-Path $PSScriptRoot "check-debug-env.ps1")
Write-Host "Setup complete. Future starts: .\scripts\start-debug.ps1" -ForegroundColor Green
