@echo off

:: --- EXECUTION ---
echo Compressing %sourceDir% into %destinationZip%...
"C:\Program Files\7-Zip\7z.exe" a -tzip citybus.zip vehicles

if %ERRORLEVEL% EQU 0 (
    echo Compression successful!

    :: Move to BeamNG folder
    copy citybus.zip "C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive\content\vehicles\citybus.zip"
) else (
    echo Compression failed with error code %ERRORLEVEL%.
)
