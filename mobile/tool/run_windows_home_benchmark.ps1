$ErrorActionPreference = 'Stop'

$iterationCount = 10
$acceptanceMilliseconds = 2000.0
$mobileRoot = Split-Path -Parent $PSScriptRoot
$databasePath = Join-Path ([IO.Path]::GetTempPath()) 'lar_finance_task9_benchmark.sqlite'
$markerPath = Join-Path ([IO.Path]::GetTempPath()) 'lar_finance_task9_benchmark.ready.json'
$executablePath = Join-Path $mobileRoot 'build\windows\x64\runner\Profile\lar_finance.exe'

Push-Location $mobileRoot
try {
    & flutter build windows --profile --target tool/benchmark_home.dart `
        --dart-define=LAR_FINANCE_API_BASE_URL=https://financeiro.palmbook.online/api/v1
    if ($LASTEXITCODE -ne 0) { throw 'Windows profile benchmark build failed.' }

    foreach ($path in @($databasePath, "$databasePath-wal", "$databasePath-shm", "$databasePath-journal", $markerPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }

    function Invoke-BenchmarkLaunch {
        if (Test-Path -LiteralPath $markerPath) {
            Remove-Item -LiteralPath $markerPath -Force
        }
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $process = Start-Process -FilePath $executablePath -WindowStyle Hidden -PassThru
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while (-not (Test-Path -LiteralPath $markerPath)) {
            if ($process.HasExited) {
                throw "Benchmark exited before rendering Home (exit $($process.ExitCode))."
            }
            if ([DateTime]::UtcNow -ge $deadline) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                throw 'Benchmark did not render Home within 30 seconds.'
            }
            Start-Sleep -Milliseconds 10
        }
        $stopwatch.Stop()
        if (-not $process.WaitForExit(5000)) {
            Stop-Process -Id $process.Id -Force
            throw 'Benchmark did not exit after publishing readiness.'
        }
        if ($process.ExitCode -ne 0) {
            throw "Benchmark exited with code $($process.ExitCode)."
        }
        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        if ($marker.ready -ne $true) { throw 'Benchmark readiness marker is invalid.' }
        return $stopwatch.Elapsed.TotalMilliseconds
    }

    [void](Invoke-BenchmarkLaunch) # Warm-up and deterministic dataset seed.
    $samples = for ($iteration = 0; $iteration -lt $iterationCount; $iteration++) {
        Invoke-BenchmarkLaunch
    }
    $sorted = @($samples | Sort-Object)
    $median = ($sorted[4] + $sorted[5]) / 2.0
    $p95 = $sorted[[Math]::Ceiling($iterationCount * 0.95) - 1]
    $accepted = $median -lt $acceptanceMilliseconds
    $result = [ordered]@{
        iterations = $iterationCount
        samples_ms = @($samples | ForEach-Object { [Math]::Round($_, 3) })
        median_ms = [Math]::Round($median, 3)
        p95_ms = [Math]::Round($p95, 3)
        accepted = $accepted
        acceptance_ms = $acceptanceMilliseconds
        accounts = 20
        categories = 50
        transactions = 10000
        measurement = 'process launch to first populated Home frame'
    }
    $json = $result | ConvertTo-Json -Compress
    Write-Output "LAR_FINANCE_BENCHMARK=$json"
    if (-not $accepted) { exit 1 }
}
finally {
    Pop-Location
}
