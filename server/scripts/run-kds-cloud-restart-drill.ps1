param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'debug-env-common.ps1')

$repoRoot = Get-DebugRepoRoot
Import-DebugEnv (Join-Path $repoRoot '.env.debug')
Assert-DebugDatabaseUrl $env:DEBUG_DB_URL
if ($env:DEBUG_DB_URL -notmatch '^jdbc:mysql://([^:/?]+):(\d+)/([^?]+)') {
    throw 'Unsupported DEBUG_DB_URL'
}
$dbHost = $Matches[1]
$dbPort = $Matches[2]
$dbName = $Matches[3]
$mysql = Get-MySqlCommand
$previousMySqlPassword = $env:MYSQL_PWD
$env:MYSQL_PWD = $env:DEBUG_DB_PASSWORD

function Invoke-DrillSql([string]$Statement) {
    $result = & $mysql --batch --skip-column-names --raw `
        "--host=$dbHost" "--port=$dbPort" "--user=$env:DEBUG_DB_USERNAME" `
        $dbName "--execute=$Statement" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Debug SQL failed: $result"
    }
    return $result
}

function Invoke-KdsChanges([string]$Token) {
    return Invoke-RestMethod `
        -Uri 'http://127.0.0.1:18080/kds/v2/changes?after_seq=0' `
        -Headers @{'X-Kds-Device-Token' = $Token} `
        -TimeoutSec 10
}

function Assert-KdsWebSocketPong([string]$Token, [long]$Cursor) {
    $socket = [Net.WebSockets.ClientWebSocket]::new()
    $socket.Options.SetRequestHeader('X-Kds-Device-Token', $Token)
    $timeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(10))
    try {
        $uri = [Uri]"ws://127.0.0.1:18080/ws/kds/v2?shop_id=1&after_seq=$Cursor"
        [void]$socket.ConnectAsync($uri, $timeout.Token).GetAwaiter().GetResult()
        $payload = [Text.Encoding]::UTF8.GetBytes('ping')
        [void]$socket.SendAsync(
            [ArraySegment[byte]]::new($payload),
            [Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            $timeout.Token
        ).GetAwaiter().GetResult()
        $buffer = New-Object byte[] 256
        $received = $socket.ReceiveAsync(
            [ArraySegment[byte]]::new($buffer),
            $timeout.Token
        ).GetAwaiter().GetResult()
        $response = [Text.Encoding]::UTF8.GetString($buffer, 0, $received.Count)
        if ($response -ne '{"type":"pong"}') {
            throw 'Unexpected KDS WebSocket response'
        }
        [void]$socket.CloseAsync(
            [Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
            'done',
            [Threading.CancellationToken]::None
        ).GetAwaiter().GetResult()
    } finally {
        $timeout.Dispose()
        $socket.Dispose()
    }
}

function Start-DrillServer {
    if (Get-NetTCPConnection -LocalPort 18080 -State Listen -ErrorAction SilentlyContinue) {
        return
    }
    $stdout = Join-Path $repoRoot '.ai-runtime\cloud-restart-drill.out.log'
    $stderr = Join-Path $repoRoot '.ai-runtime\cloud-restart-drill.err.log'
    $pwsh = (Get-Process -Id $PID).Path
    $startScript = Join-Path $repoRoot 'scripts\start-debug.ps1'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`""
    $launcher = Start-Process -FilePath $pwsh -ArgumentList $arguments `
        -WindowStyle Hidden -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr -PassThru
    $deadline = (Get-Date).AddSeconds(60)
    do {
        Start-Sleep -Milliseconds 500
        try {
            $health = Invoke-WebRequest -UseBasicParsing `
                -Uri 'http://127.0.0.1:18080/kds-demo.html' -TimeoutSec 2
            $ready = $health.StatusCode -eq 200
        } catch {
            $ready = $false
        }
    } until ($ready -or $launcher.HasExited -or (Get-Date) -ge $deadline)
    if (-not $ready) {
        throw "Debug server restart failed; launcherExited=$($launcher.HasExited)"
    }
}

function ConvertTo-SqlText([string]$Encoded) {
    if ($Encoded -eq '-') { return 'NULL' }
    return "CAST(FROM_BASE64('$Encoded') AS CHAR)"
}

function ConvertTo-SqlDate([string]$Encoded) {
    if ($Encoded -eq '-') { return 'NULL' }
    return "CAST(CAST(FROM_BASE64('$Encoded') AS CHAR) AS DATETIME)"
}

$beforeCounts = Invoke-DrillSql @'
SELECT
  (SELECT COUNT(*) FROM t_kds_ticket),
  (SELECT COUNT(*) FROM t_kds_v2_command),
  (SELECT COUNT(*) FROM t_kds_v2_event),
  (SELECT COALESCE(MAX(event_seq),0) FROM t_kds_v2_event_cursor)
'@
$snapshot = Invoke-DrillSql @'
SELECT id,
  IFNULL(TO_BASE64(device_token),'-'),
  IFNULL(TO_BASE64(token_hash),'-'),
  IFNULL(TO_BASE64(CAST(token_expires_at AS CHAR)),'-'),
  IFNULL(TO_BASE64(CAST(token_revoked_at AS CHAR)),'-'),
  IFNULL(TO_BASE64(CAST(last_heartbeat_at AS CHAR)),'-'),
  enabled,
  IFNULL(TO_BASE64(CAST(updated_at AS CHAR)),'-')
FROM t_kds_device
WHERE shop_id=1 AND screen_tag IS NOT NULL
ORDER BY id LIMIT 1
'@
$fields = "$snapshot" -split "`t"
if ($fields.Count -ne 8) { throw 'Unable to snapshot a debug KDS device' }
$deviceId = [int64]$fields[0]
$token = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $tokenHash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($token)) |
        ForEach-Object { $_.ToString('x2') })
} finally {
    $sha.Dispose()
}

$recovered = $false
try {
    $credentialUpdate = "UPDATE t_kds_device SET device_token=NULL,token_hash='$tokenHash'," +
        "token_expires_at=DATE_ADD(NOW(),INTERVAL 1 HOUR),token_revoked_at=NULL," +
        "last_heartbeat_at=NOW(),enabled=1,updated_at=NOW() WHERE id=$deviceId"
    Invoke-DrillSql $credentialUpdate | Out-Null

    $before = Invoke-KdsChanges $token
    $beforeCursor = [long]$before.event_seq
    $beforeEvents = $before.events | ConvertTo-Json -Depth 100 -Compress
    Assert-KdsWebSocketPong $token $beforeCursor

    $listener = Get-NetTCPConnection -LocalPort 18080 -State Listen | Select-Object -First 1
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
    if (-not (Test-DebugApplicationCommandLine $process.CommandLine $repoRoot)) {
        throw 'Refusing to stop an unrelated process on port 18080'
    }
    Stop-Process -Id $listener.OwningProcess
    Wait-Process -Id $listener.OwningProcess -Timeout 20 -ErrorAction SilentlyContinue
    if (Get-NetTCPConnection -LocalPort 18080 -State Listen -ErrorAction SilentlyContinue) {
        throw 'Debug server did not stop'
    }

    $unexpectedlyReachable = $false
    try {
        Invoke-WebRequest -UseBasicParsing `
            -Uri 'http://127.0.0.1:18080/kds-demo.html' -TimeoutSec 2 | Out-Null
        $unexpectedlyReachable = $true
    } catch { }
    if ($unexpectedlyReachable) { throw 'Debug server remained reachable after stop' }

    Start-DrillServer
    $after = Invoke-KdsChanges $token
    $afterEvents = $after.events | ConvertTo-Json -Depth 100 -Compress
    if ([long]$after.event_seq -ne $beforeCursor -or $afterEvents -ne $beforeEvents) {
        throw 'Cursor or event window changed across cloud restart'
    }
    Assert-KdsWebSocketPong $token $beforeCursor
    $recovered = $true
} finally {
    try { Start-DrillServer } catch { }
    $restore = "UPDATE t_kds_device SET " +
        "device_token=$(ConvertTo-SqlText $fields[1])," +
        "token_hash=$(ConvertTo-SqlText $fields[2])," +
        "token_expires_at=$(ConvertTo-SqlDate $fields[3])," +
        "token_revoked_at=$(ConvertTo-SqlDate $fields[4])," +
        "last_heartbeat_at=$(ConvertTo-SqlDate $fields[5])," +
        "enabled=$($fields[6]),updated_at=$(ConvertTo-SqlDate $fields[7]) " +
        "WHERE id=$deviceId"
    Invoke-DrillSql $restore | Out-Null
    $afterCounts = Invoke-DrillSql @'
SELECT
  (SELECT COUNT(*) FROM t_kds_ticket),
  (SELECT COUNT(*) FROM t_kds_v2_command),
  (SELECT COUNT(*) FROM t_kds_v2_event),
  (SELECT COALESCE(MAX(event_seq),0) FROM t_kds_v2_event_cursor)
'@
    $restoredSql = "SELECT IFNULL(TO_BASE64(device_token),'-')," +
        "IFNULL(TO_BASE64(token_hash),'-')," +
        "IFNULL(TO_BASE64(CAST(token_expires_at AS CHAR)),'-')," +
        "IFNULL(TO_BASE64(CAST(token_revoked_at AS CHAR)),'-')," +
        "IFNULL(TO_BASE64(CAST(last_heartbeat_at AS CHAR)),'-'),enabled," +
        "IFNULL(TO_BASE64(CAST(updated_at AS CHAR)),'-') " +
        "FROM t_kds_device WHERE id=$deviceId"
    $restored = Invoke-DrillSql $restoredSql
    Write-Output "CLOUD_RESTART_RECOVERY=$recovered"
    Write-Output "BUSINESS_STATE_UNCHANGED=$($beforeCounts -eq $afterCounts)"
    Write-Output "DEVICE_RESTORED=$(($fields[1..7] -join "`t") -eq "$restored")"
    $env:MYSQL_PWD = $previousMySqlPassword
}

if (-not $recovered) { exit 1 }
