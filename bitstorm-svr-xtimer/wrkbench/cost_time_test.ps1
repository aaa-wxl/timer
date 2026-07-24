param(
    [string]$Counts = "1,50,100,200,500,1000,2000",
    [string]$OutFile = "logs\cost-time-results.csv",
    [int]$LeadMinutes = 3,
    [int]$TargetSecond = 0
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$RunLog = "logs\cost-time-run.log"

function Log([string]$message) {
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $message
    Add-Content -Path $RunLog -Value $line
    Write-Host $line
}

function MysqlRow([string]$sql) {
    $lines = docker exec -e MYSQL_PWD=PaiSmart2025 mysql mysql -uroot --database=bitstorm-svr -N -e $sql
    return ($lines | Where-Object { $_ -match "^\d" } | Select-Object -Last 1)
}

function MysqlScalar([string]$sql) {
    $row = MysqlRow $sql
    if ([string]::IsNullOrWhiteSpace($row)) { return 0 }
    return [int](($row -split "`t")[0])
}

function RedisZCard([string]$key) {
    $lines = docker exec -e REDISCLI_AUTH=PaiSmart2025 redis redis-cli --raw ZCARD $key
    $value = ($lines | Where-Object { $_ -match "^\d+$" } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($value)) { return 0 }
    return [int]$value
}

function RedisReadyCount([datetime]$target) {
    $minute = $target.ToString("yyyy-MM-dd HH:mm")
    $sum = 0
    for ($i = 0; $i -lt 5; $i++) {
        $sum += RedisZCard ("{0}_{1}" -f $minute, $i)
    }
    return $sum
}

function Assert-Port([int]$port) {
    $line = netstat -ano | Select-String ":$port" | Select-String "LISTENING" | Select-Object -First 1
    if (-not $line) { throw "port $port is not listening" }
}

function Clean-State {
    Log "cleaning mysql and redis"
    docker exec -e MYSQL_PWD=PaiSmart2025 mysql mysql -uroot --database=bitstorm-svr -N -e "SET FOREIGN_KEY_CHECKS=0; TRUNCATE TABLE timer_task; TRUNCATE TABLE xtimer; SET FOREIGN_KEY_CHECKS=1;" | Out-Null
    docker exec -e REDISCLI_AUTH=PaiSmart2025 redis redis-cli FLUSHDB | Out-Null
    try { Invoke-RestMethod -Uri "http://127.0.0.1:9999/reset" -TimeoutSec 5 | Out-Null } catch {}
}

function Next-Target {
    $base = (Get-Date).AddMinutes($LeadMinutes)
    return [datetime]::new($base.Year, $base.Month, $base.Day, $base.Hour, $base.Minute, $TargetSecond, [DateTimeKind]::Local)
}

function Wait-Ready([int]$count, [datetime]$target, [long]$targetMs) {
    $deadline = $target.AddSeconds(-5)
    $dbReady = 0
    $redisReady = 0
    do {
        $dbReady = MysqlScalar "SELECT COUNT(*) FROM timer_task WHERE run_timer=$targetMs AND status=0;"
        $redisReady = RedisReadyCount $target
        if ($dbReady -ge $count -and $redisReady -ge $count) { break }
        Log "waiting ready count=$count db=$dbReady redis=$redisReady"
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return @($dbReady, $redisReady)
}

function Wait-Finished([int]$count, [long]$targetMs) {
    $deadline = (Get-Date).AddSeconds(45)
    do {
        $finished = MysqlScalar "SELECT COUNT(*) FROM timer_task WHERE run_timer=$targetMs AND status IN (2,3);"
        if ($finished -ge $count) { return $finished }
        Log "waiting finished count=$count finished=$finished"
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    return $finished
}

function Run-One([int]$count) {
    Clean-State

    $target = Next-Target
    $targetMs = ([DateTimeOffset]$target).ToUnixTimeMilliseconds()
    $cron = "$TargetSecond $($target.Minute) * * * ?"
    $callback = "http://127.0.0.1:9999/echo"
    $url = "http://127.0.0.1:8082/xtimer/batchCreateTimers?count=$count&cron=$([uri]::EscapeDataString($cron))&callbackUrl=$([uri]::EscapeDataString($callback))"

    Log "creating timers count=$count target=$($target.ToString("HH:mm:ss"))"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $resp = Invoke-RestMethod -Method Post -Uri $url -TimeoutSec 240
    $sw.Stop()
    Log "create finished count=$count ms=$($sw.ElapsedMilliseconds)"

    $ready = Wait-Ready $count $target $targetMs
    Log "ready count=$count db=$($ready[0]) redis=$($ready[1])"

    try { Invoke-RestMethod -Uri "http://127.0.0.1:9999/reset" -TimeoutSec 5 | Out-Null } catch {}
    $sleep = [math]::Max(0, [int][math]::Ceiling(($target - (Get-Date)).TotalSeconds))
    Log "waiting target count=$count sleepSeconds=$sleep"
    if ($sleep -gt 0) { Start-Sleep -Seconds $sleep }

    $finished = Wait-Finished $count $targetMs
    $db = MysqlRow "SELECT COUNT(*), SUM(status=2), SUM(status=3), SUM(status=0), SUM(cost_time<1000), MIN(cost_time), AVG(cost_time), MAX(cost_time) FROM timer_task WHERE run_timer=$targetMs;"
    $parts = $db -split "`t"

    $maxCost = if ($parts[7] -and $parts[7] -ne "NULL") { [double]$parts[7] } else { $null }
    $readyComplete = ($ready[0] -eq $count -and $ready[1] -eq $count)
    $sampleValid = ($readyComplete -and $finished -eq $count)
    $pass = ($sampleValid -and $maxCost -ne $null -and $maxCost -lt 1000)
    Log "result count=$count readyComplete=$readyComplete maxCost=$maxCost success=$($parts[1]) failed=$($parts[2]) pass=$pass"

    [pscustomobject]@{
        taskCount = $count
        target = $target.ToString("HH:mm:ss")
        created = $resp.data.success
        dbReady = $ready[0]
        redisReady = $ready[1]
        readyComplete = $readyComplete
        finished = $finished
        sampleValid = $sampleValid
        dbTotal = [int]$parts[0]
        dbSuccess = [int]$parts[1]
        dbFailed = [int]$parts[2]
        dbPending = [int]$parts[3]
        dbUnder1s = [int]$parts[4]
        minCost = $parts[5]
        avgCost = $parts[6]
        maxCost = $parts[7]
        costTimePass = $pass
    }
}

[void](New-Item -ItemType Directory -Force -Path (Split-Path $OutFile))
"" | Set-Content -Path $RunLog
"taskCount,target,created,dbReady,redisReady,readyComplete,finished,sampleValid,dbTotal,dbSuccess,dbFailed,dbPending,dbUnder1s,minCost,avgCost,maxCost,costTimePass" | Set-Content -Path $OutFile

if ($TargetSecond -lt 0 -or $TargetSecond -gt 59) { throw "TargetSecond must be 0..59" }
Assert-Port 8082
Assert-Port 9999
Log "using existing app and echo; no per-count restart"

$countList = $Counts -split "," | ForEach-Object { [int]$_.Trim() }
$results = foreach ($count in $countList) {
    $result = Run-One $count
    $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16}" -f `
        $result.taskCount, $result.target, $result.created, $result.dbReady, $result.redisReady, `
        $result.readyComplete, $result.finished, $result.sampleValid, $result.dbTotal, $result.dbSuccess, $result.dbFailed, $result.dbPending, `
        $result.dbUnder1s, $result.minCost, $result.avgCost, $result.maxCost, $result.costTimePass
    Add-Content -Path $OutFile -Value $line
    Write-Output $result
    $result
}

$results | Format-Table -AutoSize
