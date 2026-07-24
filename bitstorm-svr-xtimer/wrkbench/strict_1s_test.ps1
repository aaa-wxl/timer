param(
    [int[]]$Counts = @(500, 1000, 1500, 2000),
    [string]$OutFile = "logs\strict-1s-results.csv"
)

$ErrorActionPreference = "Stop"
$java = Join-Path $env:JAVA_HOME "bin\java.exe"
$jar = "target\bitstorm-svr-xtimer.jar"
$RunLog = "logs\strict-1s-run.log"

function Log([string]$message) {
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $message
    Add-Content -Path $RunLog -Value $line
    Write-Output $line
}

function MysqlScalar([string]$sql) {
    $lines = docker exec -e MYSQL_PWD=PaiSmart2025 mysql mysql -uroot --database=bitstorm-svr -N -e $sql
    return ($lines | Where-Object { $_ -match "^\d+(\.\d+)?$" } | Select-Object -Last 1)
}

function MysqlRow([string]$sql) {
    $lines = docker exec -e MYSQL_PWD=PaiSmart2025 mysql mysql -uroot --database=bitstorm-svr -N -e $sql
    return ($lines | Where-Object { $_ -match "^\d+" } | Select-Object -Last 1)
}

function Stop-App {
    Log "checking app on 8082"
    $line = netstat -ano | Select-String ":8082" | Select-String "LISTENING" | Select-Object -First 1
    if ($line) {
        $appProcId = [int](($line -split "\s+")[-1])
        Log "stopping app pid=$appProcId"
        Stop-Process -Id $appProcId -Force
        Start-Sleep -Seconds 3
    }
}

function Clean-State {
    Log "cleaning mysql and redis"
    docker exec -e MYSQL_PWD=PaiSmart2025 mysql mysql -uroot --database=bitstorm-svr -N -e "SET FOREIGN_KEY_CHECKS=0; TRUNCATE TABLE timer_task; TRUNCATE TABLE xtimer; SET FOREIGN_KEY_CHECKS=1; FLUSH STATUS;" | Out-Null
    docker exec -e REDISCLI_AUTH=PaiSmart2025 redis redis-cli FLUSHDB | Out-Null
    Invoke-RestMethod -Uri "http://127.0.0.1:9999/reset" -TimeoutSec 10 | Out-Null
}

function Start-App {
    Log "starting app"
    $args = @(
        "-jar", $jar,
        "--spring.profiles.active=dev",
        "--mybatis.configuration.log-impl=org.apache.ibatis.logging.nologging.NoLoggingImpl",
        "--trigger.pool.corePoolSize=250",
        "--trigger.pool.maxPoolSize=250"
    )
    $proc = Start-Process -FilePath $java -ArgumentList $args -WorkingDirectory (Get-Location) -RedirectStandardOutput "logs\app-8082-strict.out.log" -RedirectStandardError "logs\app-8082-strict.err.log" -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddSeconds(45)
    do {
        $listening = netstat -ano | Select-String ":8082" | Select-String "LISTENING"
        if ($listening) {
            Log "app listening pid=$($proc.Id)"
            return $proc.Id
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "app did not listen on 8082"
}

function Run-One([int]$count) {
    Log "run count=$count start"
    Stop-App
    Clean-State
    $appId = Start-App

    $base = (Get-Date).AddMinutes(3)
    $target = [datetime]::new($base.Year, $base.Month, $base.Day, $base.Hour, $base.Minute, 0, [DateTimeKind]::Local)
    $targetMs = ([DateTimeOffset]$target).ToUnixTimeMilliseconds()
    $cron = "0 $($target.Minute) * * * ?"
    $callback = "http://127.0.0.1:9999/echo?targetMs=$targetMs"
    $url = "http://127.0.0.1:8082/xtimer/batchCreateTimers?count=$count&cron=$([uri]::EscapeDataString($cron))&callbackUrl=$([uri]::EscapeDataString($callback))"

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Log "creating timers count=$count target=$($target.ToString("HH:mm:ss"))"
    $resp = Invoke-RestMethod -Method Post -Uri $url -TimeoutSec 240
    $sw.Stop()
    Log "create finished count=$count ms=$($sw.ElapsedMilliseconds)"

    $deadline = (Get-Date).AddSeconds(160)
    $ready = 0
    do {
        $readyText = MysqlScalar "SELECT COUNT(*) FROM timer_task WHERE run_timer=$targetMs;"
        $ready = [int]$readyText
        if ($ready -ge $count) { break }
        Log "waiting timer_task ready count=$count ready=$ready"
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    Log "timer_task ready count=$count ready=$ready"

    Invoke-RestMethod -Uri "http://127.0.0.1:9999/reset" -TimeoutSec 10 | Out-Null
    $sleep = [math]::Max(0, [int][math]::Ceiling(($target - (Get-Date)).TotalSeconds + 5))
    Log "waiting trigger count=$count sleepSeconds=$sleep"
    if ($sleep -gt 0) { Start-Sleep -Seconds $sleep }

    $echo = Invoke-RestMethod -Uri "http://127.0.0.1:9999/stats" -TimeoutSec 10
    $db = MysqlRow "SELECT COUNT(*), SUM(status=2), SUM(status=3), SUM(status=0), SUM(status=2 AND cost_time<1000), MIN(CASE WHEN status=2 THEN cost_time END), AVG(CASE WHEN status=2 THEN cost_time END), MAX(CASE WHEN status=2 THEN cost_time END) FROM timer_task WHERE run_timer=$targetMs;"
    $parts = $db -split "`t"
    Log "result count=$count echoCount=$($echo.count) echoMax=$($echo.max) dbSuccess=$($parts[1]) dbFailed=$($parts[2]) dbMax=$($parts[7])"

    [pscustomobject]@{
        taskCount = $count
        appPid = $appId
        target = $target.ToString("HH:mm:ss")
        createMs = $sw.ElapsedMilliseconds
        created = $resp.data.success
        ready = $ready
        echoCount = $echo.count
        echoMaxMs = $echo.max
        echoP99Ms = $echo.p99
        echoUnder1s = $echo.under_1s
        dbSuccess = [int]$parts[1]
        dbFailed = [int]$parts[2]
        dbUnder1s = [int]$parts[4]
        dbMaxMs = if ($parts[7]) { [double]$parts[7] } else { $null }
        passStrict1s = ($echo.count -eq $count -and $echo.max -lt 1000 -and [int]$parts[2] -eq 0)
    }
}

[void](New-Item -ItemType Directory -Force -Path (Split-Path $OutFile))
"" | Set-Content -Path $RunLog
"taskCount,target,created,ready,echoCount,echoMaxMs,echoP99Ms,echoUnder1s,dbSuccess,dbFailed,dbUnder1s,dbMaxMs,passStrict1s" | Set-Content -Path $OutFile

try {
    $results = foreach ($count in $Counts) {
        $result = Run-One $count
        $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12}" -f `
            $result.taskCount, $result.target, $result.created, $result.ready, $result.echoCount, `
            $result.echoMaxMs, $result.echoP99Ms, $result.echoUnder1s, $result.dbSuccess, `
            $result.dbFailed, $result.dbUnder1s, $result.dbMaxMs, $result.passStrict1s
        Add-Content -Path $OutFile -Value $line
        Write-Output $result
        $result
    }

    $results | Format-Table -AutoSize
} catch {
    Log "ERROR $($_.Exception.Message)"
    Log "ERROR $($_.ScriptStackTrace)"
    throw
}
