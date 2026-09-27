# Запуск хоста и N клиентов в режиме разработки (ENet, без Steam) — раздел 3 SPEC.
#
# Использование (из корня проекта):
#   powershell -ExecutionPolicy Bypass -File tools\run_local.ps1 [-Clients 3]
#
# Закрытие окон — вручную или остановкой процессов Godot.
param(
    [int]$Clients = 3
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Godot = "godot"
if (-not (Get-Command $Godot -ErrorAction SilentlyContinue)) {
    $Godot = "godot4"
}

$HostArgs = @("--path", $Root, "--", "--dev-host", "--dev-name=Host")
Write-Host "Хост ENet 127.0.0.1:7777 + $Clients клиент(ов)…"
Start-Process -FilePath $Godot -ArgumentList $HostArgs
Start-Sleep -Seconds 2

for ($i = 1; $i -le $Clients; $i++) {
    $ClientArgs = @("--path", $Root, "--", "--dev-join=127.0.0.1", "--dev-name=Bot$i")
    Start-Process -FilePath $Godot -ArgumentList $ClientArgs
}
