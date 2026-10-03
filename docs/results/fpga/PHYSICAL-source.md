# RING — controlador físico Arty A7-35T

## Resultado verificado

Bitstream: `build/ring_fpga_top.bit` (2.192.216 bytes).
Top: `ring_fpga_top`. Part: `xc7a35tcsg324-1`.
Vivado 2026.1 completó síntesis, implementación, routing y bitgen.

| Comprobación | Resultado |
|---|---|
| Regresión NN | 30.243 vectores, 100%, hidden/logits/action, 0 discrepancias |
| UART end-to-end | 38 STATE de referencia, inputs y ACT exactos |
| Casos adicionales UART | CRLF, tick cero/leading zeros, tick INT64 máximo, ±2% baud, malformed, break y recuperación, frame mientras ocupado |
| Deadline de los 38 intercambios | Menos de 16,67 ms desde primer byte STATE hasta ACT completo |
| DRC | 0 infracciones; NSTD-1 y UCIO-1 resueltos mediante pins/IOSTANDARD reales |
| Setup global WNS / TNS | +0,186 ns / 0 ns |
| Hold global WHS / THS | +0,048 ns / 0 ns |
| Endpoints internos sin restricciones | 0 |
| CDC | Cruces entre relojes relacionados safely timed; RX con sincronizador de dos FF |
| LUT / registros | 1.687 (8,11%) / 1.659 (3,99%) |
| RAMB18 / DSP / BUFG | 1 / 0 / 2 |

**El margen de setup es pequeño (186 ps).** El build actual pasa el modelo de
timing post-route; cualquier cambio de RTL, constraints o toolchain debe
repetir implementación y timing. UART, NN y ambos controladores físicos
se verificaron en una partida RING de 40 segundos con el driver COM5 a 1 ms.

Reportes: `build/timing.txt`, `build/drc.txt`, `build/cdc.txt`,
`build/utilization.txt`, `build/synth_utilization.txt`, `build_ring.log`.
Logs funcionales: `nn_regression.log`, `uart_sim.log`.

## Protocolo comprobado en RING

Se inspeccionaron `Project #15/src/SerialController.cs`, `UartProtocol.cs`,
`PongGame.cs`, `Controllers.cs` y `docs/UART.md`, `docs/DUAL-UART.md`.
No se modificaron Windows ni STM32.

115200 baud, 8N1, sin flow control ni DTR/RTS. El divisor del reloj es
868 ciclos a 100 MHz (115207,37 baud, error +0,0064%).

```text
STATE,1,tick,L|R,ball_x,ball_y,vx,vy,own_paddle_y,opponent_paddle_y,width,height,paddle_height\n
ACT,1,tick,UP|STAY|DOWN\n
```

13 campos STATE y 4 campos ACT. Posiciones en píxeles lógicos; velocidades
en píxeles/segundo; origen arriba a la izquierda. El host redondea primero
sus números a enteros con ties away from zero; la FPGA recibe esos enteros.
Tick no negativo hasta 9223372036854775807, aceptando ceros iniciales y
devolviendo la representación decimal canónica del mismo valor.
LF delimita cada línea y se acepta CRLF. Máximo 192 caracteres sin LF.
El timeout del host es 1000/60 ms. El enum de C# tiene un orden diferente
al modelo; se transmiten los nombres, nunca sus valores numéricos:
NN 0→UP, 1→STAY, 2→DOWN.

## Adaptación de entrada autorizada

`PongGame.cs` confirma `BallSpeed=540`, width=960 y height=480.
Para R: x=ball_x/width; y=ball_y/height; vx=vx_px/540;
vy=vy_px/540; paddle_y=own_paddle_y/height.
Para L: x=(width-ball_x)/width; vx=-vx_px/540; y/vy/paddle_y iguales.

Cada componente se convierte a `clip(round_even(127 * componente), -127,127)`.
La implementación usa razones enteras exactas, sin floats. Un divisor
restaurador secuencial calcula cociente y resto; el resto permite redondear
al par. Se amplía a 33 bits antes de reflejar/negar para evitar overflow
con INT32_MIN. Valores fuera de rango se saturan.
`generate_uart_vectors.py` implementa una referencia independiente con
`fractions.Fraction`, seguida de la NN NumPy sin cambios.

Esta es una adaptación física nueva, autorizada por el usuario: el entrenamiento
solo contenía estados normalizados y no definía una escala física de velocidad.
La equivalencia de la NN está demostrada; no implica una accuracy del 88,75%
sobre partidas reales ni una trayectoria docente idéntica a la física de RING.
No se cambiaron pesos, biases, SH ni el RTL de `pong_nn.sv`.

## Arquitectura y errores resueltos

UART RX sincroniza la entrada y muestrea en el centro de cada bit. Una trama
con stop inválido emite error y espera que la línea vuelva a reposo.
Parser streaming comprueba header, versión, side, tick e INT32 sin overflow,
dimensiones positivas y 0<paddle_height<=height. Ignora tramas inválidas
hasta LF. No acepta un nuevo frame mientras procesa/transmite el anterior;
descarta el frame completo recibido en ese intervalo. No mantiene una cola.
El siguiente LF permite recuperarse; coincide con la resincronización del host.

FSM: WAIT_FRAME captura el estado; Q_PREP registra la perspectiva adaptada;
Q_START/Q_WAIT cuantizan los cinco componentes; NN_START/NN_ACCEPT mantienen
start hasta busy; NN_WAIT espera done; SEND_BYTE/WAIT_TX transmiten ACT.
El tick se captura antes de ejecutar la NN y se conserva hasta terminar TX.

UART, parser, normalizador y coordinación trabajan a **100 MHz**. La NN
intacta trabaja con un reloj relacionado de **50 MHz**, generado por un
divisor registrado y distribuido por BUFG. Su máximo es 2.196 ciclos,
43,92 µs. XDC declara ambos relojes y los cruces se temporizan; no hay
false paths entre ellos. Inputs estables durante toda la inferencia;
start permanece activo hasta busy y done dura dos ciclos del reloj padre.

El primer build a 100 MHz falló timing en la MAC de la NN (-0,607 ns).
Se resolvió con el reloj derivado sin modificar la NN. El siguiente build
falló en la preparación del numerador (-0,533 ns); se resolvió registrando
adaptación y magnitud/escalado en etapas separadas. No se relajó el reloj.
Las únicas excepciones temporales son RX asíncrono→primer sincronizador y
las salidas externas asíncronas TX/LED. No se degradó ningún DRC.

En el testbench se corrigieron una representación CR no compatible con XSim
(ahora byte explícito 0x0D) y una acción STAY supuesta para el centro; el
modelo real responde DOWN para [64,64,0,0,64]. No eran cambios de la NN.
XSim puede devolver exit code 0 tras `$fatal`; `simulate_ring.ps1` exige PASS
y ausencia de Fatal en el log. La advertencia de sensibilidad de XSim sobre
el argumento fijo de una tarea del testbench no afecta al RTL ni a los tests.

LEDs toggle: led[0] byte RX, led[1] STATE válido, led[2] NN done,
led[3] ACT completamente enviado. Son indicadores de actividad, no pulsos
estirados ni contadores de errores. Reset interno de arranque: ~655 µs.

## Reproducir tests y bitstream

Desde PowerShell, en `fpga/build/work`:

```powershell
.\simulate_ring.ps1
$vivado = 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat'
& $vivado -mode batch -source build_ring.tcl -log build_ring.log -journal build_ring.jou
if ($LASTEXITCODE -ne 0) { throw 'Vivado build failed' }
```

No requiere proyecto GUI; el Tcl especifica top, fuentes, part y XDC.
El build detiene bitgen si setup o hold fallan. No programa la placa.

## Conexión y detección física

Conectar la Arty por **micro-USB PROG/UART J10**, con cable de datos.
El puente FTDI integrado proporciona USB-JTAG y UART/VCP: no hace falta
adaptador USB-UART externo ni cablear PMOD. UART es interna al PCB:
FPGA RX **A9** (`uart_txd_in` en el Master XDC, PC TX), FPGA TX **D10**
(`uart_rxd_out` en el Master XDC, PC RX). El top usa nombres desde la
perspectiva FPGA: `uart_rx_in` y `uart_tx_out`. Reloj E3; LEDs H5/J5/T9/T10;
todos LVCMOS33. Los nombres del Master XDC están desde la perspectiva del PC,
como explica la sección 8 del
[manual Digilent](https://mm.digikey.com/Volume0/opasdata/d220001/medias/docus/781/Arty_A7_RM_Web.pdf).

Pins verificados en `Arty-A7-35-Master.xdc` y
el [XDC oficial Digilent](https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-35-Master.xdc).
El [demo oficial Arty A7-35T](https://github.com/Digilent/Arty-A7-35-GPIO)
documenta el uso del puente UART desde el PC por el mismo micro-USB.

Detección realizada: cable Digilent **[BOARD_JTAG_SERIAL_REDACTED]**, dispositivo
**xc7a35t_0 / PART=xc7a35t**. Ver `hardware_detected.txt`.
La enumeración real usada por RING (`Checks.exe --list-ports`) detecta:
COM4 STLink VID_0483/PID_374E; **COM5 FTDI VID_0403/PID_6010/MI_01**.
CIM solo listó COM4; no usar exclusivamente CIM para enumerar VCP FTDI.
COM5 es el candidato, todavía sin prueba ACT física. Confirmarlo observando
qué puerto desaparece/reaparece al desconectar/reconectar la Arty. No abrir
COM4 en una prueba FPGA. Ver `ports_detected.txt`.

## Programar SRAM y probar manualmente

En la comprobación inicial no se programó la placa. Posteriormente se cargó
el diseño en SRAM para investigar el timeout UART; ver el diagnóstico al final.
Para repetir la carga, en Hardware Manager:
Open Target → Auto Connect → seleccionar `xc7a35t_0` → Program Device →
usar `build/ring_fpga_top.bit`. No elegir configuración de memoria flash.
Alternativa desde esta carpeta, con hw_server activo (Hardware Manager lo inicia):

```powershell
& 'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat' -mode batch -source program_sram.tcl
```

El script exige un solo target y un solo xc7a35t y usa únicamente
`program_hw_devices`. Carga SRAM volátil; no escribe flash. Al quitar la
alimentación la placa pierde este diseño y podría cargar el anterior de flash;
hay que volver a programar SRAM para esta prueba.

Cerrar RING y terminales que ocupen el COM de FPGA antes del smoke test.
Usar Windows PowerShell 5.1 para disponer de System.IO.Ports:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uart_smoke.ps1 -PortName COM5
```

Envía LF de resincronización y:
`STATE,1,42,R,480,240,0,0,240,240,960,480,80`.
Respuesta exacta del modelo: `ACT,1,42,DOWN`. El script cierra el puerto.
Esta prueba confirma comunicación; su timeout de 1 s es deliberadamente
diagnóstico y no valida el deadline de RING.

Después de un PASS y de confirmar COM5, arrancar ambos controladores:

```powershell
& 'host/RING Windows\bin\PongExperiment.exe' --fpga-mode serial --fpga-port COM5 --stm32-mode serial --stm32-port COM4
```

Si la enumeración cambia, sustituir COM5 por el puerto confirmado. Windows
debe pasar de WAITING a CONNECTED, aumentar RX/APPLY y registrar ACT en
`Project #15/bin/logs/fpga-uart.log`. No asumir éxito solo porque abre el puerto.
STM32, física, scoring y rendering se mantienen tal como estaban.

## Diagnóstico físico posterior al timeout

Se cargó `build/ring_fpga_top.bit` mediante JTAG; startup HIGH, sin flash.
COM5 se abre, pero la prueba recibió **0 bytes** en 1 s. La registry de FTDI
identifica COM5 como canal B `[BOARD_UART_SERIAL_REDACTED]`, asociado al mismo dispositivo
que JTAG `[BOARD_JTAG_SERIAL_REDACTED]`.

La simulación funcional del netlist post-route con primitivas Xilinx pasa
el STATE de smoke y responde `ACT,1,42,DOWN`; ver `netlist_smoke.log`.
La licencia Vivado BASIC bloquea `create_debug_core` (ILA), así que no se
generó ni cargó el diseño ILA. Alternativamente se generó y cargó en SRAM
un diseño temporal que conecta D10 directamente a A9, sin UART, parser,
normalizador ni NN. El eco `PING,42` también terminó en timeout.

Esto localiza el problema en el camino físico/pinout/puente/driver, sin
demostrar todavía cuál es la causa concreta. **Es necesario confirmar el
modelo exacto y revisión impresos en la placa**: JTAG xc7a35t no distingue
la Arty A7 de otras placas con el mismo chip. No cambiar pines suponiendo
otro modelo. `uart_smoke.ps1` ahora indica cuántos bytes parciales recibió.
El bitstream normal se restauró correctamente en SRAM (`restore_normal.log`,
startup HIGH). El usuario identifica la serigrafía como ARTY / DIGILENT / AVNET;
faltan revisión y comprobación visual de conexiones. Los pins no se cambiaron.
También se restableció únicamente el canal B FTDI a UART mediante
`FT_SetBitMode(handle,0,0)` y se probó el driver D2XX directamente:
45 bytes enviados, 0 recibidos. No se tocó la EEPROM del FTDI, JTAG-A ni flash.
El uso de reset de modo está documentado por
[FTDI](https://ftdichip.com/Support/Knowledgebase/ft_setbitmode.htm).
En este punto histórico la comunicación física seguía pendiente; ver la
corrección y los resultados físicos posteriores más abajo.

La foto posterior confirma una Arty original, con XC7A35T-CSG324. Se contrastó
también el [Arty-Master.xdc oficial](https://github.com/Digilent/digilent-xdc/blob/master/Arty-Master.xdc)
para Arty Rev. B: E3 (clock), A9 (FPGA RX), D10 (FPGA TX) y H5/J5/T9/T10 (LEDs)
coinciden con el diseño. La revisión exacta no se distingue en la foto.
En esa imagen J10 está sin cable, y la enumeración posterior solo muestra
COM4: COM5 ya no está conectado. Tras reconectar y perder alimentación hay
que cargar nuevamente el bitstream en SRAM antes del smoke test.

**Causa encontrada:** se había interpretado al revés la dirección de las
señales del Master XDC. `uart_rxd_out` corresponde a la recepción del PC,
por tanto es salida de FPGA en D10; `uart_txd_in` corresponde a transmisión
del PC, por tanto es entrada de FPGA en A9. No era un problema de la NN,
del protocolo ni del modelo de placa. Se corrigieron constraints y nombres
de puertos y se reconstruyó el loopback: **PASS PHYSICAL LOOPBACK COM5 : PING,42**.
La observación del usuario de un LED fijo y otro parpadeando confirmó antes
de la corrección que el diseño estaba cargado y el reloj activo.

El controlador completo corregido se reconstruyó y cargó en SRAM. DRC 0;
setup +0,186 ns, hold +0,048 ns. Smoke real:
**PASS COM5 115200 8N1: ACT,1,42,DOWN**. `uart_hardware_vectors.ps1`
comparó 38 STATE de referencia reales con el ACT NumPy esperado:
**38/38 correctos**. También se repitieron las simulaciones RTL: 30.243
vectores NN y 38 STATE UART, todos PASS.

### Latencia de Windows FTDI antes de ejecutar RING

La primera medición física (driver LatencyTimer=16 ms) dio:
mínimo 8,5493 ms, media 15,9406 ms, máximo 26,9268 ms;
16 de 38 intercambios excedieron 16,67 ms. Evidencia:
`hardware_vectors_default_latency.json`. Reducir temporalmente el chip a
1 ms por D2XX no persiste al abrir VCP: la segunda medición todavía dio
19 de 38 sobre el deadline. No se modificó el timeout de Windows.

Se intentó guardar LatencyTimer=1 para el canal B/COM5, pero Windows
denegó acceso al registro; **no se cambió ese parámetro persistente**.
`ftdi_driver_latency_before.json` registra el valor original 16 y la ruta
exacta. Este ajuste de driver requiere administrador:

1. Administrador de dispositivos → Puertos (COM y LPT).
2. USB Serial Port (COM5) → Propiedades → Configuración del puerto.
3. Opciones avanzadas → Latency Timer (msec) → **1** → Aceptar.
4. Cerrar y volver a abrir COM5. Si Windows pide reconectar, volver a
   programar SRAM después de reconectar.
5. Ejecutar `uart_hardware_vectors.ps1 -PortName COM5` para repetir la
   medición, y después ejecutar RING con los parámetros ya documentados.

Solo ajustar el puerto FTDI COM5; no cambiar COM4 del STM32. Es un ajuste
reversible del driver Windows, no una escritura a EEPROM/flash. No se
considera demostrado todavía el cumplimiento físico del deadline ni una
partida RING completa hasta repetir la medición con ese ajuste.

### Ajuste aplicado y partida física verificada

Se elevó `apply_com5_latency.ps1` mediante el consentimiento UAC de Windows
y se guardó **LatencyTimer=1 ms** solo para COM5. COM4 no se modificó.
La repetición de los 38 STATE dio 38/38 correctos, media 10,2925 ms,
un único pico de 66,2631 ms; por ello se comprobó además una partida real.

`physical_match_low_latency/match.txt` registra una partida de 40 segundos,
4.800 pasos físicos y 2.400 decisiones por lado:

| Métrica | FPGA COM5 | STM32 COM4 |
|---|---:|---:|
| STATE enviados | 2.351 | 2.346 |
| ACT recibidos | 2.351 | 2.346 |
| Acciones aplicadas | 2.326 (98,94% de enviados) | 2.331 (99,36%) |
| Timeouts / inválidos / errores de conexión | 0 / 0 / 0 | 0 / 0 / 0 |
| Última latencia | 8,88 ms | 8,32 ms |
| Golpes de pala | 9 | 10 |

Marcador final 0–1. La prueba se cerró automáticamente (exit 0) y liberó
ambos COM. La aplicación de acciones FPGA subió desde ~31% observado en
la partida previa a ~99%; esto resuelve el cuello de botella de fluidez.
No garantiza ganar al STM32 ni ausencia de jitter en cualquier carga de Windows.
La física, el modelo, el firmware STM32 y el deadline de RING no se cambiaron.
El ajuste es reversible: LatencyTimer de COM5 puede volver a 16 mediante
Opciones avanzadas del driver. El bitstream continúa cargado en SRAM;
reiniciar RING no requiere volver a programarlo mientras la placa conserve alimentación.
