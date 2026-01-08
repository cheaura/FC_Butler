
Add-Type -AssemblyName System.Drawing

$sourceDir = "D:\fconline4_app\app_screenshot"
$destDir = "D:\fconline4_app\app_screenshot\resized"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

# 타겟 해상도: 6.5인치 디스플레이 (1242 x 2688)
$targetWidth = 1242
$targetHeight = 2688

$files = Get-ChildItem -Path $sourceDir -Filter "Simulator Screenshot*.png"

foreach ($file in $files) {
    try {
        $img = [System.Drawing.Image]::FromFile($file.FullName)
        
        # 새 비트맵 생성
        $newImg = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
        $graph = [System.Drawing.Graphics]::FromImage($newImg)
        
        # 품질 설정
        $graph.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graph.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graph.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        
        # 이미지 그리기 (리사이징)
        $graph.DrawImage($img, 0, 0, $targetWidth, $targetHeight)
        
        # 저장
        $newPath = Join-Path $destDir $file.Name
        $newImg.Save($newPath, [System.Drawing.Imaging.ImageFormat]::Png)
        
        # 리소스 해제
        $img.Dispose()
        $newImg.Dispose()
        $graph.Dispose()
        
        Write-Host "변환 완료: $($file.Name)"
    }
    catch {
        Write-Host "오류 발생 ($($file.Name)): $_"
    }
}

Write-Host "모든 이미지가 D:\fconline4_app\app_screenshot\resized 폴더에 저장되었습니다."
