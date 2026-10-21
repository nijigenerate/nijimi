param(
    [Parameter(Mandatory=$true)][string]$Model,
    [Parameter(Mandatory=$true)][string]$NijiliveDll,
    [Parameter(Mandatory=$true)][string]$NicxliveDll,
    [string]$Viewer = (Join-Path $PSScriptRoot '../nijimi-opengl.exe'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../test-output'),
    [ValidateRange(1,120)][int]$Frames = 3
)
$ErrorActionPreference = 'Stop'
$Model = (Resolve-Path -LiteralPath $Model).Path
$Viewer = (Resolve-Path -LiteralPath $Viewer).Path
$variants = [ordered]@{
    nijilive = (Resolve-Path -LiteralPath $NijiliveDll).Path
    nicxlive = (Resolve-Path -LiteralPath $NicxliveDll).Path
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
foreach ($name in $variants.Keys) {
    $capture = Join-Path $OutputDirectory "$name.png"
    $log = Join-Path $OutputDirectory "$name.log"
    if (Test-Path -LiteralPath $capture) {
        Remove-Item -LiteralPath $capture
    }
    & $Viewer $Model 720 720 --unity-dll $variants[$name] --test --frames $Frames --no-transparent-window --capture $capture *> $log
    if ($LASTEXITCODE -ne 0) { throw "$name failed: see $log" }
    if (!(Test-Path -LiteralPath $capture)) { throw "$name did not produce a capture" }
    Get-Content -LiteralPath $log | Select-String '\[capture\]|initialized .* parameter'
}
@{
    model = (Get-FileHash -LiteralPath $Model -Algorithm SHA256).Hash
    viewer = (Get-FileHash -LiteralPath $Viewer -Algorithm SHA256).Hash
    nijilive = (Get-FileHash -LiteralPath $variants.nijilive -Algorithm SHA256).Hash
    nicxlive = (Get-FileHash -LiteralPath $variants.nicxlive -Algorithm SHA256).Hash
    frames = $Frames
    fixedDeltaSeconds = 1.0 / 60.0
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'inputs.json') -Encoding UTF8
Write-Output "Both runs completed. Compare the PNG files; successful execution does not imply rendering equivalence."