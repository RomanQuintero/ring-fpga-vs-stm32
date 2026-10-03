param([string]$PortName='COM5')
$ErrorActionPreference='Stop'
if($PortName -eq 'COM4') {throw 'Do not probe STM32'}
$s=[System.IO.Ports.SerialPort]::new($PortName,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$s.Handshake=[System.IO.Ports.Handshake]::None
$s.DtrEnable=$false; $s.RtsEnable=$false
$s.ReadTimeout=1000; $s.NewLine="`n"
try {
 $s.Open(); Start-Sleep -Milliseconds 100; $s.DiscardInBuffer()
 $s.Write("PING,42`n")
 $reply=$s.ReadLine().TrimEnd([char]13)
 if($reply -ne 'PING,42') {throw "Wrong physical echo: $reply"}
 Write-Output "PASS PHYSICAL LOOPBACK $PortName : $reply"
} finally {if($s.IsOpen) {$s.Close()}; $s.Dispose()}
