param(
    [string]$Counts = "900,950,1000"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$RunLog = "logs\pool-ab-run.log"
$java = Join-Path $env:JAVA_HOME "bin\java.exe"
$jar = "target\bitstorm-svr-xtimer.jar"

function Log([string]$message) {
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $message
    Add-Content -Path $RunLog -Value $line
    Write-Host $line
}

function Stop-App {
    $line = netstat -ano | Select-String ":8082" | Select-String "LISTENING" | Select-Object -First 1
    if ($line) {
        $appPid = [int](($line -split "\s+")[-1])
        Log "stopping app pid=$appPid"
        Stop-Process -Id $appPid -Force
        Start-Sleep -Seconds 4
    }
}

function Start-App([string]$name, [int]$triggerCore, [int]$triggerMax, [int]$queue, [int]$druidMax) {
    Stop-App
    Log "starting $name trigger=$triggerCore/$triggerMax queue=$queue druid=$druidMax"
    $args = @(
        "-jar", $jar,
        "--spring.profiles.active=dev",
        "--mybatis.configuration.log-impl=org.apache.ibatis.logging.nologging.NoLoggingImpl",
        "--trigger.pool.corePoolSize=$triggerCore",
        "--trigger.pool.maxPoolSize=$triggerMax",
        "--trigger.pool.queueCapacity=$queue",
        "--spring.datasource.druid.max-active=$druidMax"
    )
    $proc = Start-Process -FilePath $java -ArgumentList $args -WorkingDirectory (Get-Location) `
        -RedirectStandardOutput "logs\app-8082-$name.out.log" `
        -RedirectStandardError "logs\app-8082-$name.err.log" `
        -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds(60)
    do {
        $listening = netstat -ano | Select-String ":8082" | Select-String "LISTENING"
        if ($listening) {
            Log "$name listening pid=$($proc.Id)"
            Start-Sleep -Seconds 15
            return
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "$name did not listen on 8082"
}

function Run-Scenario([string]$name, [int]$triggerCore, [int]$triggerMax, [int]$queue, [int]$druidMax) {
    Start-App $name $triggerCore $triggerMax $queue $druidMax
    $outFile = "logs\cost-time-$name.csv"
    Log "running $name counts=$Counts"
    & .\wrkbench\cost_time_test.ps1 -Counts $Counts -OutFile $outFile
    Log "finished $name"
}

[void](New-Item -ItemType Directory -Force -Path "logs")
"" | Set-Content -Path $RunLog

docker exec -e MYSQL_PWD=PaiSmart2025 mysql mysql -uroot -N -e "SHOW VARIABLES LIKE 'max_connections';" | Out-File "logs\pool-ab-mysql-before.txt"

Run-Scenario "A-core150-druid150" 150 250 10000 150
Run-Scenario "B-core250-druid150" 250 250 10000 150

Log "raising mysql max_connections to 300 for C"
docker exec -e MYSQL_PWD=PaiSmart2025 mysql mysql -uroot -N -e "SET GLOBAL max_connections=300;" | Out-Null
docker exec -e MYSQL_PWD=PaiSmart2025 mysql mysql -uroot -N -e "SHOW VARIABLES LIKE 'max_connections';" | Out-File "logs\pool-ab-mysql-after.txt"
Run-Scenario "C-core250-druid250" 250 250 10000 250

Log "all scenarios finished"
