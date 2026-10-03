param([string]$Toolchain = '')
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    if (!$Toolchain) {
        $command = Get-Command arm-none-eabi-gcc.exe -ErrorAction SilentlyContinue
        if ($command) { $Toolchain = Split-Path $command.Source }
        else {
            $compiler = Get-ChildItem 'C:/ST' -Filter arm-none-eabi-gcc.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if (!$compiler) { throw 'Indica -Toolchain con la carpeta bin de GNU Tools for STM32.' }
            $Toolchain = $compiler.DirectoryName
        }
    }
    $gcc = Join-Path $Toolchain 'arm-none-eabi-gcc.exe'
    $rtos = 'Middlewares/Third_Party/FreeRTOS/Source'
    $includes = @('Core/Inc', 'Drivers/STM32H7xx_HAL_Driver/Inc',
        'Drivers/STM32H7xx_HAL_Driver/Inc/Legacy', 'Drivers/CMSIS/Include',
        'Drivers/CMSIS/Device/ST/STM32H7xx/Include', "$rtos/include",
        "$rtos/CMSIS_RTOS_V2", "$rtos/portable/GCC/ARM_CM7/r0p1")
    $flags = @('-mcpu=cortex-m7', '-mthumb', '-mfpu=fpv5-d16', '-mfloat-abi=hard')
    $compile = $flags + @('-std=gnu11', '-g3', '-Og', '-Wall', '-Wextra',
        '-ffunction-sections', '-fdata-sections', '-DUSE_PWR_DIRECT_SMPS_SUPPLY',
        '-DUSE_HAL_DRIVER', '-DSTM32H7A3xxQ', '--specs=nano.specs')
    $compile += $includes | ForEach-Object { '-I' + $_ }
    $sources = @(Get-ChildItem 'Core/Src/*.c', 'Drivers/STM32H7xx_HAL_Driver/Src/*.c', "$rtos/*.c" | Select-Object -ExpandProperty FullName)
    $sources += @("$rtos/CMSIS_RTOS_V2/cmsis_os2.c", "$rtos/portable/MemMang/heap_4.c",
        "$rtos/portable/GCC/ARM_CM7/r0p1/port.c", 'Core/Startup/startup_stm32h7a3zitxq.s')
    New-Item -ItemType Directory -Force Build | Out-Null
    $objects = @()
    foreach ($source in $sources) {
        $object = 'Build/' + [IO.Path]::GetFileNameWithoutExtension($source) + '.o'
        & $gcc @compile -c $source -o $object
        if ($LASTEXITCODE -ne 0) { throw "Error compilando $source" }
        $objects += $object
    }
    & $gcc @flags @objects '-TSTM32H7A3ZITXQ_FLASH.ld' '--specs=nosys.specs' '--specs=nano.specs' '-Wl,--gc-sections' '-Wl,-Map=Build/PongSTM32.map' '-Wl,--start-group' '-lc' '-lm' '-Wl,--end-group' -o Build/PongSTM32.elf
    if ($LASTEXITCODE -ne 0) { throw 'Error de enlazado' }
    & (Join-Path $Toolchain 'arm-none-eabi-size.exe') Build/PongSTM32.elf
} finally { Pop-Location }
