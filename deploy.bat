@echo off


del "%destinationZip%" /y 2>nul
:: --- EXECUTION ---
echo Compressing %sourceDir% into %destinationZip%...
"C:\Program Files\7-Zip\7z.exe" a -tzip citibus.zip vehicles

if %ERRORLEVEL% EQU 0 (
    echo Compression successful!

    :: Move to BeamNG folder
    move citybus.zip "C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive\content\vehicles\"
) else (
    echo Compression failed with error code %ERRORLEVEL%.
)
