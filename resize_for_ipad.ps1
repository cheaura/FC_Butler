
Add-Type -AssemblyName System.Drawing

# 원본은 아까 만든 JPG 파일들 사용 (final 폴더)
$sourceDir = "D:\fconline4_app\app_screenshot\final"
$destDir = "D:\fconline4_app\app_screenshot\ipad"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

# 아이패드 12.9형/13형 필수 해상도: 2048 x 2732
$targetWidth = 2048
$targetHeight = 2732

$files = Get-ChildItem -Path $sourceDir -Filter "*.jpg"

foreach ($file in $files) {
    try {
        $img = [System.Drawing.Image]::FromFile($file.FullName)
        
        # 새 비트맵 생성 (아이패드 크기)
        $newImg = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
        $graph = [System.Drawing.Graphics]::FromImage($newImg)
        
        # 흰색 배경 채우기 (혹시 모를 투명도 대비)
        $graph.Clear([System.Drawing.Color]::White)
        
        # 품질 설정
        $graph.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graph.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        
        # 이미지 내 중앙 정렬해서 그리기 (비율 유지하면 여백 생기므로 꽉 채우기 - Stretch)
        # 비율 유지보단 꽉 채우는 게 심사엔 유리합니다 (여백 있으면 리젝 가능성)
        $graph.DrawImage($img, 0, 0, $targetWidth, $targetHeight)
        
        # 저장
        $newPath = Join-Path $destDir $file.Name
        $newImg.Save($newPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        
        $img.Dispose()
        $newImg.Dispose()
        $graph.Dispose()
        
        Write-Host "iPad용 변환 완료: $($newPath)"
    }
    catch {
        Write-Host "오류: $_"
    }
}
Write-Host "iPad용 이미지가 D:\fconline4_app\app_screenshot\ipad 폴더에 생성되었습니다."
