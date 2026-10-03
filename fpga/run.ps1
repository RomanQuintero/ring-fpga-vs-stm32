param(
    [ValidateSet('Prepare','Simulate','Build','Synthesize')][string]$Task = 'Simulate',
    [string]$Python = 'python',
    [string]$VivadoBin = ''
)
$ErrorActionPreference = 'Stop'
$work = Join-Path $PSScriptRoot 'build/work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
foreach ($folder in @('rtl','constraints','sim','tools')) {
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $work -Force
    }
}
foreach ($model in @('pong_mlp.npz','pong_mlp_int8.npz')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../ml/$model") -Destination $work -Force
}
function Run-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed ($LASTEXITCODE)" }
}
function Tool([string]$Name) {
    if ($VivadoBin) { return Join-Path $VivadoBin ($Name + '.bat') }
    return $Name
}
Write-Host "Prepared isolated working directory: $work"
if ($Task -eq 'Prepare') { return }
Push-Location $work
try {
    if ($Task -eq 'Simulate') {
        Run-Checked $Python @('generate_vectors.py')
        Run-Checked $Python @('generate_uart_vectors.py')
        Run-Checked (Tool 'xvlog') @('-sv','uart_rx.sv','uart_tx.sv','state_parser.sv','input_quantizer.sv','pong_nn.sv','ring_fpga_top.sv','tb_pong_nn.sv','tb_ring_fpga_top.sv')
        foreach ($test in @(@('tb_pong_nn','pong_nn_sim','nn_regression.log','PASS: 30243'),@('tb_ring_fpga_top','ring_uart_sim','uart_sim.log','PASS UART: 38'))) {
            Run-Checked (Tool 'xelab') @($test[0],'-s',$test[1])
            Run-Checked (Tool 'xsim') @($test[1],'-runall','-log',$test[2])
            $result = Get-Content -LiteralPath $test[2] -Raw
            if ($result -notmatch [regex]::Escape($test[3]) -or $result -match 'Fatal:') { throw "Simulation failed: $($test[2])" }
        }
    } else {
        $script = if ($Task -eq 'Build') { 'build_ring.tcl' } else { 'synth_check.tcl' }
        Run-Checked (Tool 'vivado') @('-mode','batch','-source',$script)
    }
} finally { Pop-Location }
