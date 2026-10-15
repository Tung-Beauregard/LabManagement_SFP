# Started by the sfplab-nist: link that tools\nist-bridge-install.cmd registers (the GC-MS page's
# "啟動 NIST 連線程式" button). Windows may append the link to the command line; with no param block it
# lands in $args and is ignored on purpose, so nothing from a web page reaches a command line or the bridge's
# options. The only thing this does is open tools\nist-bridge.cmd in a minimised window.
Start-Process -FilePath (Join-Path $PSScriptRoot 'nist-bridge.cmd') -WindowStyle Minimized
