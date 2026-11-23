# Une el equipo al dominio. PowerShell como administrador:  powershell -ExecutionPolicy Bypass -File C:\acc\unir.ps1 -Nombre PC-SEDE02-01
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]{1,15}$')][string]$Nombre)
Remove-Item C:\Windows\System32\Sysprep\clon.xml,C:\Windows\Panther\unattend.xml -ErrorAction SilentlyContinue   # llevan la contraseña local
Resolve-DnsName -Type SRV _ldap._tcp.ad.alcaldia.lab -ErrorAction Stop | Out-Null
w32tm /resync /force | Out-Null
Add-Computer -DomainName ad.alcaldia.lab -NewName $Nombre -Credential (Get-Credential -Message 'Cuenta de Domain Admins (p. ej. ALCALDIA\admin.dc)') -ErrorAction Stop
Restart-Computer -Confirm
