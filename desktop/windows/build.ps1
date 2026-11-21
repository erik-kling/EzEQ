param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '1.2.0')
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$zip = Join-Path $PSScriptRoot 'vendor\VBCABLE_Driver_Pack45.zip'
$expected = 'B950E39F01AF1D04EA623C8F6D8EB9B6EA5C477C637295FABF20631C85116BFB'
New-Item -ItemType Directory -Path (Split-Path $zip) -Force | Out-Null
if (!(Test-Path $zip)) {
    Invoke-WebRequest -Uri 'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip' -OutFile $zip
}
if ((Get-FileHash -Algorithm SHA256 $zip).Hash -ne $expected) {
    throw 'The VB-CABLE archive does not match the pinned SHA-256.'
}

$check = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
try {
    Expand-Archive -LiteralPath $zip -DestinationPath $check
    if (!(Test-Path (Join-Path $check 'VBCABLE_Setup_x64.exe') -PathType Leaf)) {
        throw 'VB-CABLE Setup is missing from the verified archive.'
    }
} finally {
    Remove-Item -LiteralPath $check -Recurse -Force -ErrorAction SilentlyContinue
}

python -m PyInstaller --noconfirm EzEQ.spec
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller failed.' }
$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
& $iscc "/DVersion=$Version" (Join-Path $PSScriptRoot 'EzEQ.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed.' }
