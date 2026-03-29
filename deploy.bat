@echo off


del "%destinationZip%" /y 2>nul
:: --- EXECUTION ---
echo Compressing %sourceDir% into %destinationZip%...
"C:\Program Files\7-Zip\7z.exe" a -tzip citybus.zip vehicles

if %ERRORLEVEL% EQU 0 (
    echo Compression successful!

    :: Move to BeamNG folder
    move citybus.zip "C:\Users\admin-local\AppData\Local\BeamNG\BeamNG.drive\current\mods"
) else (
    echo Compression failed with error code %ERRORLEVEL%.
)
