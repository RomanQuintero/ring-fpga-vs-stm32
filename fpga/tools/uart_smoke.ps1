param([Parameter(Mandatory=$true)][string]$PortName)
$ErrorActionPreference='Stop'
if ($PortName -notmatch '^COM[0-9]+$' -or $PortName -eq 'COM4') {
    throw 'Specify the verified Arty COM port, distinct from STM32 COM4.'
}
$serial = [System.IO.Ports.SerialPort]::new($PortName,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$serial.Handshake=[System.IO.Ports.Handshake]::None
$serial.DtrEnable=$false
$serial.RtsEnable=$false
$serial.NewLine="`n"
$serial.ReadTimeout=1000
$serial.WriteTimeout=1000
try {
    $serial.Open()
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()
    $serial.Write("`nSTATE,1,42,R,480,240,0,0,240,240,960,480,80`n")
    $buffer=[System.Text.StringBuilder]::new()
    $clock=[System.Diagnostics.Stopwatch]::StartNew()
    $serial.ReadTimeout=50
    $complete=$false
    while($clock.ElapsedMilliseconds -lt 1000) {
        try { $value=$serial.ReadByte() } catch [System.TimeoutException] { continue }
        if($value -eq 10) { $complete=$true; break }
        [void]$buffer.Append([char]$value)
    }
    if(-not $complete) {
        $hex=([System.Text.Encoding]::ASCII.GetBytes($buffer.ToString()) | ForEach-Object { $_.ToString('X2') }) -join ' '
        throw "UART timeout on $PortName : received $($buffer.Length) bytes; hex=[$hex]. Verify loaded bitstream, board COM identity and RX/STATE/NN/TX LEDs."
    }
    $reply=$buffer.ToString().TrimEnd([char]13)
    if ($reply -ne 'ACT,1,42,DOWN') { throw "Unexpected reply: $reply" }
    Write-Output "PASS $PortName 115200 8N1: $reply"
} finally { if($serial.IsOpen) {$serial.Close()}; $serial.Dispose() }
