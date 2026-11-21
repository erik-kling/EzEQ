param([switch]$Unpack)

# 0: usable endpoints; 2: new driver present, endpoints may need a restart;
# 1: absent; 3: enumeration failed.
$ErrorActionPreference = 'Stop'
try {
    if ($Unpack) {
        Expand-Archive -LiteralPath (Join-Path $PSScriptRoot 'VBCABLE_Driver_Pack45.zip') `
            -DestinationPath (Join-Path $PSScriptRoot 'VB-CABLE') -Force
        exit 0
    }
    $devices = @(Get-PnpDevice -PresentOnly | Where-Object Status -eq 'OK')
    $endpoints = $devices | Where-Object Class -eq 'AudioEndpoint'
    $render = $endpoints | Where-Object FriendlyName -like 'CABLE Input (*VB-Audio*'
    $capture = $endpoints | Where-Object FriendlyName -like 'CABLE Output (*VB-Audio*'
    if ($render -and $capture) { exit 0 }
    $driver = $devices | Where-Object {
        $_.Class -eq 'Media' -and $_.FriendlyName -like 'VB-Audio Virtual Cable*'
    }
    if ($driver) { exit 2 }
    exit 1
} catch {
    exit 3
}
