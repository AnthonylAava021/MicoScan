$ErrorActionPreference = "Stop"
$proyecto = Split-Path $PSScriptRoot -Parent
$logoDir = Join-Path $proyecto "logo"
$resDir = Join-Path $proyecto "android\app\src\main\res"

$logoFile = $null
foreach ($ext in @(".png", ".jpg", ".jpeg", ".webp")) {
    $p = Join-Path $logoDir "SPLASH$ext"
    if (Test-Path $p) { $logoFile = $p; break }
}
if (-not $logoFile) {
    Write-Host "No se encontró logo/SPLASH.png ni SPLASH.jpg en $logoDir" -ForegroundColor Red
    exit 1
}

Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile((Resolve-Path $logoFile))
$imgW = $img.Width
$imgH = $img.Height
$sizes = @(
    @{ dir = "mipmap-mdpi";   size = 48 },
    @{ dir = "mipmap-hdpi";   size = 72 },
    @{ dir = "mipmap-xhdpi";  size = 96 },
    @{ dir = "mipmap-xxhdpi"; size = 144 },
    @{ dir = "mipmap-xxxhdpi"; size = 192 }
)
foreach ($s in $sizes) {
    $outDir = Join-Path $resDir $s.dir
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $outPath = Join-Path $outDir "ic_launcher.png"
    $bmp = New-Object System.Drawing.Bitmap($s.size, $s.size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $scale = [Math]::Min($s.size / $imgW, $s.size / $imgH)
    $w = [int]($imgW * $scale)
    $h = [int]($imgH * $scale)
    $x = [int](($s.size - $w) / 2)
    $y = [int](($s.size - $h) / 2)
    $g.DrawImage($img, $x, $y, $w, $h)
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "Generado: $($s.dir)\ic_launcher.png"
}
$img.Dispose()
Write-Host "Iconos generados correctamente." -ForegroundColor Green
