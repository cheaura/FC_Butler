
Add-Type -AssemblyName System.Drawing

$sourceDir = "D:\fconline4_app\app_screenshot\resized"
$destDir = "D:\fconline4_app\app_screenshot\final"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

$files = Get-ChildItem -Path $sourceDir -Filter "*.png"

foreach ($file in $files) {
    try {
        $img = [System.Drawing.Image]::FromFile($file.FullName)
        
        # 투명도 제거를 위한 새 비트맵 (흰색 배경)
        $newImg = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
        $graph = [System.Drawing.Graphics]::FromImage($newImg)
        $graph.Clear([System.Drawing.Color]::White) # 배경을 흰색으로 채움
        $graph.DrawImage($img, 0, 0, $img.Width, $img.Height)
        
        # JPG로 저장
        $newPath = Join-Path $destDir ($file.BaseName + ".jpg")
        $newImg.Save($newPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        
        $img.Dispose()
        $newImg.Dispose()
        $graph.Dispose()
        
        Write-Host "JPG 변환 완료: $($newPath)"
    }
    catch {
        Write-Host "오류: $_"
    }
}
Write-Host "모든 이미지가 D:\fconline4_app\app_screenshot\final 폴더에 JPG로 저장되었습니다."
