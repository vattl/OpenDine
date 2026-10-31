# KDS 本地完整流程演示（门店 shop_id=1，需 MySQL + :8080 服务）
$ErrorActionPreference = "Stop"
$base = "http://127.0.0.1:8080"
$shopId = 1
$screenTag = "meat_grill"
$deviceCode = "KDS-LOCAL-RUN-01"

function Post-Json($path, $body, $headers = @{}) {
    $h = @{ "Content-Type" = "application/json" }
    foreach ($k in $headers.Keys) { $h[$k] = $headers[$k] }
    $json = if ($body) { $body | ConvertTo-Json -Compress } else { "{}" }
    return Invoke-RestMethod -Uri "$base$path" -Method POST -Headers $h -Body $json
}
function Get-Json($path, $headers = @{}) {
    return Invoke-RestMethod -Uri "$base$path" -Method GET -Headers $headers
}

Write-Host "`n=== 1) 设备登录 ===" -ForegroundColor Cyan
$login = Post-Json "/kds/device/login" @{
    shop_id = $shopId
    device_code = $deviceCode
    screen_tag = $screenTag
    device_name = "本地流程测试"
}
if ($login.code -ne 0) { throw "login failed: $($login | ConvertTo-Json)" }
$token = $login.device.device_token
Write-Host "token=$token screen=$($login.device.screen_tag)"

$hdr = @{ "X-Kds-Device-Token" = $token }

Write-Host "`n=== 2) 今日统计 ===" -ForegroundColor Cyan
$stats = Get-Json "/kds/stats/today" $hdr
Write-Host ($stats.stats | ConvertTo-Json -Compress)

Write-Host "`n=== 3) 待做队列 status=0 ===" -ForegroundColor Cyan
$list0 = Get-Json "/kds/order/list?status=0&pageSize=10" $hdr
$orders0 = @($list0.orders)
Write-Host "pending orders: $($orders0.Count)"

$detailId = $null
$orderId = $null
if ($orders0.Count -gt 0) {
    $orderId = $orders0[0].order_id
    $items = @($orders0[0].items)
    if ($items.Count -gt 0) { $detailId = $items[0].detail_id }
}

if (-not $detailId) {
    Write-Host "`n=== 3b) 无待做 — 查制作中 status=1 ===" -ForegroundColor Yellow
    $list1 = Get-Json "/kds/order/list?status=1&pageSize=10" $hdr
    $orders1 = @($list1.orders)
    Write-Host "cooking orders: $($orders1.Count)"
    if ($orders1.Count -gt 0) {
        $orderId = $orders1[0].order_id
        $detailId = $orders1[0].items[0].detail_id
    }
}

if ($detailId) {
    Write-Host "`n=== 4) 划菜 0->1 (detail_id=$detailId) ===" -ForegroundColor Cyan
    $s1 = Post-Json "/kds/item/status" @{
        detail_id = [int]$detailId
        status = 1
        screen_tag = $screenTag
    } $hdr
    Write-Host "status->1: code=$($s1.code) msg=$($s1.msg)"

    Write-Host "`n=== 5) 划菜 1->2 (完成) ===" -ForegroundColor Cyan
    $s2 = Post-Json "/kds/item/status" @{
        detail_id = [int]$detailId
        status = 2
        screen_tag = $screenTag
    } $hdr
    Write-Host "status->2: code=$($s2.code) msg=$($s2.msg)"
} else {
    Write-Host "`n跳过划菜：无工单。可在独立 debug 库执行: `$env:RUN_LOCAL_KDS_SMOKE='true'; mvn test -Dtest=KdsLocalSmokeTest" -ForegroundColor Yellow
}

Write-Host "`n=== 6) 划菜后统计 ===" -ForegroundColor Cyan
$stats2 = Get-Json "/kds/stats/today" $hdr
Write-Host ($stats2.stats | ConvertTo-Json -Compress)

Write-Host "`n=== 完成 ===" -ForegroundColor Green
