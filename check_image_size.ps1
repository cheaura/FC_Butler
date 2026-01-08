
Add-Type -AssemblyName System.Drawing

$path = "D:\fconline4_app\app_screenshot"
$files = Get-ChildItem -Path $path -Filter *.png

foreach ($file in $files) {
    try {
        $img = [System.Drawing.Image]::FromFile($file.FullName)
        Write-Host "$($file.Name): $($img.Width) x $($img.Height)"
        $img.Dispose()
    }
    catch {
        Write-Host "Error reading $($file.Name): $_"
    }
}
