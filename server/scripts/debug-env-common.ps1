$ErrorActionPreference = "Stop"
$script:DebugRepoRoot = Split-Path -Parent $PSScriptRoot

function Get-DebugRepoRoot {
    return $script:DebugRepoRoot
}

function Import-DebugEnv([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Debug environment file not found: $Path. Run .\scripts\setup-debug.ps1 first."
    }

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $separator = $trimmed.IndexOf("=")
        if ($separator -lt 1) {
            throw "Invalid environment line in ${Path}: $line"
        }

        $name = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid environment variable name in ${Path}: $name"
        }
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

function Assert-DebugDatabaseUrl([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) {
        throw "DEBUG_DB_URL is empty."
    }
    if ($Url -notmatch '^jdbc:mysql://127\.0\.0\.1:3307/db_diancan_debug(?:[?;]|$)') {
        throw "Safety check failed: DEBUG_DB_URL must target exactly 127.0.0.1:3307/db_diancan_debug."
    }
}

function Assert-DebugDatabaseGrants([string]$Grants) {
    if ($Grants -notmatch '(?i)db_diancan_debug') {
        throw "Debug user has no grant on db_diancan_debug."
    }
    if ($Grants -match '(?i)ON\s+`?db_diancan`?\.\*') {
        throw "Safety check failed: debug user can access production schema db_diancan."
    }
}

function Test-DebugApplicationCommandLine([string]$CommandLine, [string]$RepoRoot) {
    if ([string]::IsNullOrWhiteSpace($CommandLine) -or [string]::IsNullOrWhiteSpace($RepoRoot)) {
        return $false
    }
    $normalizedRoot = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\').ToLowerInvariant()
    $normalizedCommand = $CommandLine.ToLowerInvariant()
    return $normalizedCommand.Contains("com.lanf.application") `
            -and $normalizedCommand.Contains($normalizedRoot)
}

function Get-MySqlCommand {
    $command = Get-Command mysql.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "mysql.exe was not found. Install MySQL 8 client or add it to PATH."
    }
    return $command.Source
}

function Invoke-MySql([string]$User, [string]$Password, [string]$Sql, [int]$Port = 3307) {
    $mysql = Get-MySqlCommand
    $previousPassword = $env:MYSQL_PWD
    try {
        $env:MYSQL_PWD = $Password
        $output = & $mysql --protocol=tcp --host=127.0.0.1 --port=$Port --user=$User --batch --skip-column-names --execute=$Sql 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ($output -join [Environment]::NewLine)
        }
        return $output
    } finally {
        $env:MYSQL_PWD = $previousPassword
    }
}

function Get-MySqlServerCommand {
    $command = Get-Command mysqld.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "mysqld.exe was not found. Install MySQL 8 server or add it to PATH."
    }
    return $command.Source
}

function Start-DebugMySql {
    # A sibling worktree may intentionally reuse the repository's already
    # running isolated debug instance. Database/schema/grants are verified by
    # check-debug-env immediately after this availability check.
    if (Get-NetTCPConnection -State Listen -LocalPort 3307 -ErrorAction SilentlyContinue) {
        return
    }
    $repoRoot = Get-DebugRepoRoot
    $configFile = Join-Path $repoRoot ".local\mysql-debug\my.ini"
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        throw "Independent debug MySQL is not initialized. Run setup-debug.ps1 first."
    }

    $runtimeDir = Split-Path -Parent $configFile
    $stdoutFile = Join-Path $runtimeDir "mysqld.stdout.log"
    $stderrFile = Join-Path $runtimeDir "mysqld.stderr.log"
    $process = Start-Process -FilePath (Get-MySqlServerCommand) `
            -ArgumentList ('--defaults-file="' + $configFile + '"'), '--console' `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile

    $deadline = (Get-Date).AddSeconds(45)
    do {
        if ($process.HasExited) {
            $details = if (Test-Path $stderrFile) { (Get-Content $stderrFile -Tail 20) -join "`n" } else { "" }
            throw "Independent debug MySQL failed to start.`n$details"
        }
        Start-Sleep -Milliseconds 500
        $listening = [bool](Get-NetTCPConnection -State Listen -LocalPort 3307 -ErrorAction SilentlyContinue)
    } until ($listening -or (Get-Date) -ge $deadline)
    if (-not $listening) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "Timed out starting independent debug MySQL on port 3307."
    }
}

function New-DebugDatabasePassword {
    $bytes = New-Object byte[] 24
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    } finally {
        $generator.Dispose()
    }
    return ([BitConverter]::ToString($bytes)).Replace("-", "").ToLowerInvariant()
}
