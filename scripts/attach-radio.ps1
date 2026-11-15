# Attach the Intel Bluetooth adapter to WSL. Does not create or change a scheduled task.
# Does not start the WSL bluetooth.service. Run from Windows, not from inside WSL.
$usbipd = "C:\Program Files\usbipd-win\usbipd.exe"
if (-not (Test-Path -LiteralPath $usbipd)) {
    Write-Error "usbipd.exe is not installed at $usbipd"
    exit 1
}
$list = & $usbipd list
$list | Write-Output
$attached = $list | Where-Object { $_ -match '^\s*1-14\s+\S+\s+8087:0029\s+\S+\s+Attached\b' }
if ($attached) {
    Write-Output "bus 1-14 is already attached"
    exit 0
}
& $usbipd attach --wsl --busid 1-14
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
