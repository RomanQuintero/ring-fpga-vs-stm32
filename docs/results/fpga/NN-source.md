# Inferencia NN 5 → 16 → 3

La fase física UART/Arty está implementada: ver [PHYSICAL.md](PHYSICAL.md)
para bitstream, timing, DRC, conexión y comandos de programación/prueba.

RTL y verificación del modelo INT8 exportado, sin UART ni integración física.

## Resultado

Vivado/XSim 2026.1: **30.243 vectores, 0 discrepancias, 100% de acuerdo**
en las 16 activaciones hidden, los 3 logits enteros y la acción final.
20.000 vectores son el `X_test` real incluido en `pong_mlp.npz`; otros 243
recorren todas las combinaciones de {-128, 0, 127} y 10.000 son aleatorios
con semilla 42. Accuracy INT8 sobre `y_test`: 88,75%.

Síntesis completada para **xc7a35tcsg324-1**: 532 LUT (2,56%),
407 registros (0,98%), 1 RAMB18, 0 DSP. Ver `utilization.txt` y `synth.log`.
Sin errores ni advertencias críticas. Una advertencia de netlist indica
que una jerarquía plana no es ideal para floorplanning; no impide la síntesis.
Es sintetizable y cabe en la Arty A7-35T. No se ha hecho implementación,
asignación de pines ni cierre de timing; `timing.txt` no demuestra una
frecuencia de funcionamiento porque no se han aplicado restricciones de reloj.

## Archivos

- `pong_nn.sv`: módulo principal.
- `pong_weights.svh`: copia del header proporcionado, comprobado contra el NPZ.
- `pong_requant.svh`: constantes de requantización generadas automáticamente.
- `tb_pong_nn.sv`: comparación por vector de hidden, logits y acción; timeout y handshake.
- `generate_vectors.py`: referencia runtime y generador de vectores/umbrales.
- `vectors.txt`: 5 inputs + 16 hidden + 3 logits + acción por línea decimal.
- `reference_report.json`: propiedades verificadas del modelo y dataset.
- `pong_mlp_int8.npz`, `pong_mlp.npz`: copias de los modelos originales.
- `synth_check.tcl`: comprobación mínima de síntesis.

## Ejecutar en PowerShell

Desde esta carpeta, con Python y NumPy disponibles:

```powershell
$py = 'python'
$bin = 'C:\AMDDesignTools\2026.1\Vivado\bin'
& $py generate_vectors.py
& "$bin\xvlog.bat" -sv pong_nn.sv tb_pong_nn.sv
if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
& "$bin\xelab.bat" tb_pong_nn -s pong_nn_sim
if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
& "$bin\xsim.bat" pong_nn_sim -runall
if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
& "$bin\vivado.bat" -mode batch -source synth_check.tcl -log synth.log -journal synth.jou
```

Salida esperada: `PASS: 30243 vectors; hidden, logits and actions match Python INT8 (100%)`.
`xsim.log` conserva el resultado de la ejecución realizada.

## Contrato y arquitectura

Reset síncrono activo alto. `start` se acepta en un flanco ascendente cuando
`busy=0`; los cinco inputs signed INT8 se capturan en ese flanco. Pulsar
`start` durante un ciclo; mientras `busy=1` no se aceptan nuevas solicitudes.
`done` dura un ciclo y coincide con `busy=0` y `action` válida:
0=UP, 1=STAY, 2=DOWN. La acción se conserva hasta el siguiente resultado/reset.

FSM: `IDLE` captura inputs; `L1_INIT` carga bias; `L1_MAC` acumula los cinco
productos; `REQUANT` recorre umbrales para obtener hidden en [0,127];
`L2_INIT` carga bias de salida; `L2_MAC` acumula 16 productos; `ARGMAX`
elige el índice de mayor logit. Comparaciones estrictas conservan el primer
índice en empates, igual que NumPy. Latencia dependiente de hidden:
164 + suma(hidden) ciclos desde la aceptación a `done`, máximo 2.196 ciclos.

Matrices `W1[input][hidden]` (5,16), `W2[hidden][output]` (16,3).
Productos signed de 16 bits, extensión explícita a 32 y acumuladores/biases
signed INT32. Para cualquier entrada [-128,127], el valor absoluto del primer
acumulador queda acotado por 27.569 y el del segundo por 111.159; no hay overflow.

## Calibración y equivalencia matemática

Se inspeccionaron `train.py`, `quant.py` y `export_hdl.py` originales en la
carpeta de origen. `quant.py` calcula SH sobre todo `X_test` durante calibración:
max(ReLU(acc1))=18.670, SH=127/18.670=0.006802356722013926.
Runtime utiliza el SH guardado; nunca recalibra con el lote de inferencia.
Los biases exportados ya incluyen las escalas correspondientes y se suman
directamente. No se ha cambiado ninguna escala, peso, bias ni cuantización.

Para cada salida q=1..127 se calcula offline el menor acumulador entero cuya
operación NumPy `clip(round(acc * SH),0,127)` alcanza q. El hardware cuenta los
umbrales superados. Esto preserva incluso el comportamiento de la multiplicación
float64 y el redondeo al par, sin introducir una aproximación de punto fijo.
Se comprobó exhaustivamente esta identidad para los 27.570 acumuladores
no negativos posibles (0..27.569). Los negativos producen cero por ReLU.

No se encontraron errores matemáticos en el modelo. `train.py` imprime
erróneamente «5 → 8 → 3», aunque entrena 16 neuronas: solo es una etiqueta
desactualizada. La matriz real y el RTL usan 16. Los primeros intentos de
simulación/síntesis encontraron restricciones del sandbox; ejecutados con
autorización fuera del sandbox, ambos finalizaron correctamente.
