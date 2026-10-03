param([string]$PortName='COM5')
$ErrorActionPreference='Stop'
if($PortName -eq 'COM4') {throw 'STM32 port is not a FPGA test target'}
$frames=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'uart_vectors.txt')
$s=[System.IO.Ports.SerialPort]::new($PortName,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$s.Handshake=[System.IO.Ports.Handshake]::None
$s.DtrEnable=$false; $s.RtsEnable=$false
$s.ReadTimeout=1000; $s.NewLine="`n"
$records=@()
try {
 $s.Open(); Start-Sleep -Milliseconds 100
 for($i=0;$i -lt $frames.Count;$i+=3) {
  $s.DiscardInBuffer()
  $watch=[System.Diagnostics.Stopwatch]::StartNew()
  $s.Write($frames[$i]+"`n")
  $reply=$s.ReadLine().TrimEnd([char]13)
  $watch.Stop()
  if($reply -ne $frames[$i+1]) {throw "Case $($i/3): expected $($frames[$i+1]), got $reply"}
  $records += [pscustomobject]@{Case=$i/3;Reply=$reply;LatencyMs=$watch.Elapsed.TotalMilliseconds}
  Start-Sleep -Milliseconds 20
 }
} finally {if($s.IsOpen) {$s.Close()}; $s.Dispose()}
$records | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'hardware_vectors.json')
$summary=$records | Measure-Object -Property LatencyMs -Minimum -Maximum -Average
$late=@($records | Where-Object {$_.LatencyMs -ge 1000/60}).Count
Write-Output "PASS PHYSICAL: $($records.Count) STATE/ACT matched; min=$($summary.Minimum)ms avg=$($summary.Average)ms max=$($summary.Maximum)ms; over16.67ms=$late"
