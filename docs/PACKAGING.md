# Preparación de la carpeta

Fecha: 2026-10-03. Copia de host Windows, DroneFC, PONG_FPGA y scripts ML. Los árboles originales se mantienen intactos.

- Host: fuentes, tests, documentación y build; sin bin/ ni logs activos.
- STM32: Core, Drivers, Middlewares/Third_Party/FreeRTOS, tests, configuración de proyecto, linker scripts y `.ioc` histórico. Se mantienen licencias y código de terceros. No se incluyen Build/Debug ni Legacy de sensores/drone, ajenos al firmware Pong activo. Se omite el launch de depuración con una ruta absoluta de otro usuario; se puede crear una configuración nueva de Debug en CubeIDE.
- FPGA: RTL e includes completos; `ring_arty.xdc` renombrado a `arty-a7-35t.xdc` sin cambiar contenido. Testbenches y modelos preservados. Los scripts Tcl referencian el nuevo nombre del XDC. El wrapper prepara un workspace plano para ejecutar scripts originales sin cambiar lógica.
- ML: modelos coincidentes por SHA-256 y scripts; `quant.py` renombrado a `quantize.py` conservando contenido.
- Resultados: reportes funcionales y post-route seleccionados, referencias, métricas físicas y capturas existentes. Son históricos; no implican una ejecución nueva.
- Omitidos: `.git` internos, cachés Vivado/Python, objetos, logs temporales, ejecutables, checkpoints/bitstreams regenerables y scripts FTDI ligados al número de serie de una unidad concreta.

`source-manifest.csv` registra SHA-256 original y empaquetado de las fuentes copiadas, con estados Identical/Adapted. Renombrar un archivo no cambia su hash. Documentación traducida y referencias Tcl adaptadas se señalan como Adapted. Los archivos nuevos de preparación no tienen original que comparar.

## Privacy cleanup

Personal user/home paths, unique JTAG/UART board serial numbers and workstation details were removed from included documentation and recorded logs. Machine-specific launch/FTDI scripts were not included. Screenshots were checked for visible personal information and PNG metadata; no text/EXIF chunks were present. NPZ models contain numeric arrays only. Third-party copyright, license and vendor contact information are retained. These changes apply to the packaged copy, not the original projects.

## Checks performed on the packaged copy

- Windows host built successfully; existing physics/protocol tests and dual-controller tests passed.
- SHA-256 inventory: copied RTL, model and firmware sources retain their original bytes; only identified documentation/Tcl paths were adapted.
- FPGA workspace preparation passed. Python regenerated 30,243 NN vectors and 38 UART pairs; regenerated requantization was checked against the copied header. Xvlog parsed all relocated RTL/testbench sources successfully.
- XSim elaboration failed while compiling generated C within the restricted environment. STM32 compiler startup failed with a system-DLL relocation error in that same environment.
- Requests to repeat these two checks outside the restricted environment were rejected; neither was rerun. No new FPGA simulation/build or STM32 full-build success is claimed. Historical evidence remains separately labeled.
- Generated build folders were removed from the source package after verification.

No se ha asignado una licencia al código propio porque debe elegirla su autor. No se ha publicado nada. Destino y visibilidad del repositorio quedan pendientes.
