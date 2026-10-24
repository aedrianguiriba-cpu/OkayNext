@echo off
echo SetlistBridge Firewall Setup
echo =============================
echo.
echo Removing any old rules...
netsh advfirewall firewall delete rule name="SetlistBridge-WS" >nul 2>&1
netsh advfirewall firewall delete rule name="SetlistBridge-Beacon" >nul 2>&1
echo.
echo Adding new rules...
netsh advfirewall firewall add rule name="SetlistBridge-WS" dir=in action=allow protocol=TCP localport=9000
netsh advfirewall firewall add rule name="SetlistBridge-Beacon" dir=in action=allow protocol=UDP localport=19001
echo.
echo Done! Your phone can now reach Ableton on your local network.
pause
