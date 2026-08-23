' Launch ensure-dsh-watchdog PowerShell hidden (no console flash)
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""\\wsl.localhost\Ubuntu\home\huangzy\tools\dsh-local\scripts\ensure-dsh-watchdog.ps1""", 0, False
