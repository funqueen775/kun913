param(
    [string]$OutputPath = "$PSScriptRoot\..\assets\town\walkability_mask.png"
)

Add-Type -AssemblyName System.Drawing

$width = 1920
$height = 1080
$bitmap = [System.Drawing.Bitmap]::new($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::White)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$white = [System.Drawing.Color]::White
$brush = [System.Drawing.SolidBrush]::new($white)

function Draw-Route {
    param([int]$Width, [object[]]$Points)
    $pen = [System.Drawing.Pen]::new($white, $Width)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $typed = [System.Drawing.Point[]]@($Points | ForEach-Object { [System.Drawing.Point]::new($_[0], $_[1]) })
    $graphics.DrawLines($pen, $typed)
    $pen.Dispose()
}

function Fill-Area {
    param([object[]]$Points)
    $typed = [System.Drawing.Point[]]@($Points | ForEach-Object { [System.Drawing.Point]::new($_[0], $_[1]) })
    $graphics.FillPolygon($brush, $typed)
}

# Continuous outer pedestrian loop around the lake and rail line.
Draw-Route 78 @(
    @(70, 392), @(235, 355), @(430, 320), @(660, 300), @(920, 292),
    @(1180, 300), @(1400, 325), @(1575, 380), @(1660, 470), @(1640, 585),
    @(1530, 665), @(1370, 720), @(1190, 780), @(970, 835), @(750, 815),
    @(555, 770), @(380, 700), @(210, 660), @(70, 640)
)

# Inner lakeside promenade. It meets the outer loop at both sides and at bridges.
Draw-Route 72 @(
    @(430, 430), @(515, 385), @(665, 350), @(840, 340), @(1020, 345),
    @(1190, 375), @(1330, 425), @(1415, 500), @(1400, 585), @(1320, 655),
    @(1170, 720), @(995, 755), @(815, 740), @(665, 700), @(535, 640),
    @(455, 565), @(420, 490), @(430, 430)
)

# Main bridges and radial connections between both loops.
Draw-Route 46 @(@(535, 330), @(560, 390), @(535, 455))
Draw-Route 46 @(@(885, 305), @(875, 360), @(860, 420))
Draw-Route 46 @(@(1335, 350), @(1375, 410), @(1420, 470))
Draw-Route 46 @(@(1535, 620), @(1470, 650), @(1390, 690))
Draw-Route 46 @(@(1080, 735), @(1090, 790), @(1085, 850))
Draw-Route 46 @(@(650, 700), @(610, 750), @(570, 790))
Draw-Route 46 @(@(390, 620), @(345, 650), @(300, 675))

# Destination approach roads and usable forecourts.
Draw-Route 70 @(@(250, 355), @(250, 285), @(310, 235))
Fill-Area @(@(80,180), @(360,180), @(410,270), @(350,345), @(110,345), @(55,285))

Draw-Route 66 @(@(920, 295), @(920, 245))
Fill-Area @(@(800,215), @(1030,215), @(1080,275), @(1035,320), @(790,320), @(755,270))

Draw-Route 64 @(@(1575,380), @(1620,330), @(1665,290))
Fill-Area @(@(1490,220), @(1815,210), @(1840,345), @(1720,390), @(1510,360))

Draw-Route 68 @(@(210,660), @(205,595), @(245,540))
Fill-Area @(@(50,465), @(335,465), @(385,555), @(335,650), @(65,650))

Draw-Route 66 @(@(555,770), @(555,850))
Fill-Area @(@(410,805), @(710,805), @(735,965), @(420,980), @(390,890))

Draw-Route 62 @(@(380,700), @(350,785), @(380,855))
Fill-Area @(@(250,835), @(520,835), @(565,1025), @(255,1025), @(215,930))

Draw-Route 68 @(@(1370,720), @(1450,770))
Fill-Area @(@(1320,690), @(1660,690), @(1690,930), @(1570,970), @(1320,910))

Draw-Route 70 @(@(970,835), @(970,900))
Fill-Area @(@(770,820), @(1140,820), @(1160,1010), @(775,1010), @(735,920))

# Keep the three visible crossing structures open.
Draw-Route 42 @(@(615,770), @(635,835), @(650,900))
Draw-Route 42 @(@(1085,790), @(1085,910), @(1060,980))
Draw-Route 42 @(@(1400,655), @(1460,620), @(1515,585))

# Final rule for the prototype: every pixel is walkable except the red
# collision polygons. Blue region overlays are semantic triggers and remain
# walkable so the player can enter them.
$collisionPath = Join-Path $PSScriptRoot '..\data\town\collision.json'
$collisionData = Get-Content -Raw -LiteralPath $collisionPath | ConvertFrom-Json
$graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$blockedBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Transparent)
foreach ($layer in $collisionData.layers) {
    foreach ($polygon in $layer.polygons) {
        if ($polygon.Count -lt 3) { continue }
        $typed = [System.Drawing.Point[]]@($polygon | ForEach-Object {
            [System.Drawing.Point]::new([int]$_[0], [int]$_[1])
        })
        $graphics.FillPolygon($blockedBrush, $typed)
    }
}
$blockedBrush.Dispose()

$directory = Split-Path -Parent $OutputPath
[System.IO.Directory]::CreateDirectory($directory) | Out-Null
$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$brush.Dispose()
$graphics.Dispose()
$bitmap.Dispose()
Write-Output "WALKABILITY_MASK_BUILT $OutputPath ${width}x${height}"
