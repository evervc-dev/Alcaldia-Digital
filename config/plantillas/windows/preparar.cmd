@echo off
rem Primer inicio de la PLANTILLA: controladores virtio, ajustes y generalizado (sysprep). Lo lanza autounattend.xml.
mkdir C:\acc & for %%d in (D E F G H) do if exist %%d:\acc\unir.ps1 xcopy /y /e %%d:\acc\* C:\acc\
(for %%d in (D E F G H) do if exist %%d:\virtio-win-guest-tools.exe (start /wait %%d:\virtio-win-guest-tools.exe /install /quiet /norestart)) >> C:\acc\log.txt 2>&1
powercfg /h off & powercfg /change standby-timeout-ac 0 & powercfg /change monitor-timeout-ac 0
w32tm /config /manualpeerlist:"pool.ntp.org" /syncfromflags:manual /update
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 0 /f
del /q C:\Windows\Panther\unattend.xml C:\Windows\Panther\Unattend\unattend.xml 2>nul
echo listo>> C:\acc\log.txt
move /y C:\acc\clon.xml C:\Windows\System32\Sysprep\clon.xml
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /quiet /unattend:C:\Windows\System32\Sysprep\clon.xml
