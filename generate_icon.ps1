
Add-Type -AssemblyName System.Drawing

$width = 1024
$height = 1024
$bgColor = [System.Drawing.ColorTranslator]::FromHtml("#0C1E3C") # Dark Blue
$textColor = [System.Drawing.Color]::White

$bmp = New-Object System.Drawing.Bitmap($width, $height)
$g = [System.Drawing.Graphics]::FromImage($bmp)

$g.Clear($bgColor)

$fontFamily = New-Object System.Drawing.FontFamily("Arial")
$font = New-Object System.Drawing.Font($fontFamily, 180, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$brush = New-Object System.Drawing.SolidBrush($textColor)

$text1 = "FC"
$text2 = "Butler"

$format = New-Object System.Drawing.StringFormat
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center

# Draw FC (Upper half)
$rect1 = New-Object System.Drawing.RectangleF(0, 200, $width, 300)
$g.DrawString($text1, $font, $brush, $rect1, $format)

# Draw Butler (Lower half)
$rect2 = New-Object System.Drawing.RectangleF(0, 500, $width, 300)
$g.DrawString($text2, $font, $brush, $rect2, $format)

$bmp.Save("d:\fconline4_app\assets\icon.png", [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose()
$bmp.Dispose()
Write-Host "Icon created at d:\fconline4_app\assets\icon.png"
