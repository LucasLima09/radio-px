$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$runtime = Join-Path $PSScriptRoot '.runtime'
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'
& "$pgBin\pg_isready.exe" -h 127.0.0.1 -p 55432 -q
if ($LASTEXITCODE -ne 0) {
    & "$pgBin\pg_ctl.exe" -D "$runtime\pgdata" -l "$runtime\postgres.log" -o '-p 55432 -h 127.0.0.1' start
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel iniciar o banco.' }
}
$settings = Get-Content "$runtime\settings.json" -Raw | ConvertFrom-Json
foreach ($entry in $settings.PSObject.Properties) {
    [Environment]::SetEnvironmentVariable($entry.Name, [string]$entry.Value, 'Process')
}
$env:APK_PATH = Join-Path $PSScriptRoot 'dist\radio-px.apk'
try {
    $health = Invoke-WebRequest 'http://127.0.0.1:8080/health' -UseBasicParsing -TimeoutSec 2
} catch { $health = $null }
if (!$health -or $health.StatusCode -ne 200) {
    Start-Process -FilePath "$runtime\radio-px.exe" -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardOutput "$runtime\backend.log" -RedirectStandardError "$runtime\backend-error.log"
}
Write-Host 'Painel: http://localhost:8080/admin'
Write-Host 'APK na rede local: http://192.168.1.101:8080/downloads/radio-px.apk'
