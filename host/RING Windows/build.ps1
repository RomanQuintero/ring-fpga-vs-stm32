param([switch]$Run, [switch]$Test)
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (!(Test-Path -LiteralPath $compiler)) { throw 'The Windows .NET Framework C# compiler is required.' }
$output = Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$sources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Filter '*.cs' | ForEach-Object FullName)
& $compiler /nologo /warn:4 /warnaserror+ /optimize+ /target:winexe /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "/out:$output\PongExperiment.exe" @sources
if ($LASTEXITCODE -ne 0) { throw 'Application build failed.' }
Write-Host "Built $output\PongExperiment.exe"
if ($Test) {
    $core = @($sources | Where-Object { [IO.Path]::GetFileName($_) -ne 'Program.cs' })
    $checks = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'tests') -Filter '*.cs' | ForEach-Object FullName)
    & $compiler /nologo /warn:4 /warnaserror+ /optimize+ /target:exe "/out:$output\Checks.exe" @core @checks
    if ($LASTEXITCODE -ne 0) { throw 'Check build failed.' }
    & "$output\Checks.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Checks failed.' }
}
if ($Run) { Start-Process -FilePath (Join-Path $output 'PongExperiment.exe') }
