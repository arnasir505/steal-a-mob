# Рисует свои пиксельные текстуры 16x16 для блочного декора спавна (tools/BlockSpawn.lua).
# Текстуры нарисованы с нуля (случайные пиксели из своих палитр), чужие не используются.
# Результат: папка BlockTextures, картинки 256x256 (каждый пиксель 16x16, чтобы не размывались).
# Запуск: powershell -ExecutionPolicy Bypass -File tools/make_block_textures.ps1

Add-Type -AssemblyName System.Drawing

$out = Join-Path $PSScriptRoot "..\BlockTextures"
New-Item -ItemType Directory -Force $out | Out-Null
$rng = New-Object System.Random 7

# Случайный цвет из палитры с весами
function Pick($palette) {
    $total = 0
    foreach ($p in $palette) { $total += $p[3] }
    $roll = $rng.NextDouble() * $total
    foreach ($p in $palette) {
        $roll -= $p[3]
        if ($roll -le 0) { return $p }
    }
    return $palette[0]
}

function Save-Texture($name, [scriptblock]$pixel) {
    $small = New-Object System.Drawing.Bitmap 16, 16
    for ($y = 0; $y -lt 16; $y++) {
        for ($x = 0; $x -lt 16; $x++) {
            $c = & $pixel $x $y
            $small.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2]))
        }
    }
    $big = New-Object System.Drawing.Bitmap 256, 256
    $g = [System.Drawing.Graphics]::FromImage($big)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($small, 0, 0, 256, 256)
    $g.Dispose()
    $big.Save((Join-Path $out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $big.Dispose()
    $small.Dispose()
    Write-Host "BlockTextures/$name.png"
}

# Палитры: R, G, B, вес
$grass = @(@(96, 150, 56, 3), @(108, 164, 62, 4), @(120, 178, 70, 2), @(84, 134, 46, 2))
$dirt = @(@(134, 96, 67, 4), @(121, 86, 60, 3), @(150, 108, 75, 2), @(102, 72, 49, 2), @(128, 124, 118, 0.3))
$stone = @(@(126, 126, 126, 4), @(118, 118, 118, 3), @(137, 137, 137, 2), @(108, 108, 108, 1))
$leaves = @(@(56, 118, 38, 3), @(64, 132, 44, 3), @(46, 100, 30, 2), @(76, 146, 52, 1.5), @(32, 74, 22, 1))

Save-Texture "GrassTop" { param($x, $y) Pick $grass }
Save-Texture "Dirt" { param($x, $y) Pick $dirt }
Save-Texture "Leaves" { param($x, $y) Pick $leaves }

# Камень: серый шум и тёмные трещинки по 2-3 пикселя
$cracks = @{}
for ($k = 0; $k -lt 9; $k++) {
    $cx = $rng.Next(16); $cy = $rng.Next(16)
    $len = $rng.Next(2, 4)
    for ($s = 0; $s -lt $len; $s++) { $cracks["$(($cx + $s) % 16),$cy"] = $true }
}
Save-Texture "Stone" {
    param($x, $y)
    if ($cracks.ContainsKey("$x,$y")) { return @(96, 96, 96) }
    Pick $stone
}

# Тропинка: светлая утоптанная земля с камешками
$path = @(@(150, 120, 74, 4), @(162, 130, 82, 3), @(136, 108, 66, 2), @(124, 120, 112, 0.6))
Save-Texture "Path" { param($x, $y) Pick $path }

# Каменный кирпич: ряды по 4 пикселя, каждый второй ряд сдвинут на пол-кирпича
$brick = @(@(140, 140, 140, 4), @(132, 132, 132, 3), @(148, 148, 148, 2), @(124, 124, 124, 1))
Save-Texture "StoneBrick" {
    param($x, $y)
    $row = [math]::Floor($y / 4)
    $shift = if ($row % 2 -eq 0) { 0 } else { 4 }
    if ($y % 4 -eq 3 -or (($x + $shift) % 8) -eq 7) { return @(92, 92, 92) }
    Pick $brick
}

# Кора берёзы: светлая, с тёмными чёрточками поперёк
$birch = @(@(220, 218, 208, 4), @(232, 230, 222, 3), @(206, 204, 194, 2))
$marks = @{}
for ($k = 0; $k -lt 10; $k++) {
    $mx = $rng.Next(16); $my = $rng.Next(16)
    $len = $rng.Next(2, 5)
    for ($s = 0; $s -lt $len; $s++) { $marks["$(($mx + $s) % 16),$my"] = $true }
}
Save-Texture "BirchLog" {
    param($x, $y)
    if ($marks.ContainsKey("$x,$y")) { return @(52, 50, 46) }
    Pick $birch
}

# Кора: вертикальные полосы, у каждого столбца свой оттенок
$barkColumns = @()
for ($x = 0; $x -lt 16; $x++) {
    $barkColumns += , @(@(104, 82, 52), @(92, 72, 45), @(116, 92, 58), @(78, 60, 36))[$rng.Next(4)]
}
Save-Texture "Log" {
    param($x, $y)
    $c = $barkColumns[$x]
    if ($rng.NextDouble() -lt 0.18) { return @([int]($c[0] * 0.82), [int]($c[1] * 0.82), [int]($c[2] * 0.82)) }
    $c
}

# --- Биомы ---

# Песок: мелкий светлый шум
$sand = @(@(219, 207, 160, 4), @(210, 197, 150, 3), @(228, 217, 172, 2), @(196, 182, 136, 1))
Save-Texture "Sand" { param($x, $y) Pick $sand }

# Песчаник: горизонтальные слои, сверху светлее
Save-Texture "Sandstone" {
    param($x, $y)
    if ($y % 5 -eq 4) { return @(186, 166, 112) }
    $base = if ($y -lt 8) { 214 } else { 202 }
    $d = $rng.Next(-8, 9)
    @(($base + $d), ($base - 18 + $d), ($base - 74 + $d))
}

# Снег: почти белый с голубоватыми крапинками
$snow = @(@(246, 250, 252, 6), @(236, 242, 248, 3), @(220, 232, 244, 1))
Save-Texture "Snow" { param($x, $y) Pick $snow }

# Лёд: голубой с белыми косыми бликами
Save-Texture "Ice" {
    param($x, $y)
    if ((($x + $y) % 7) -eq 0 -and $rng.NextDouble() -lt 0.7) { return @(215, 235, 255) }
    $d = $rng.Next(-10, 11)
    @((140 + $d), (185 + $d), (240 + [math]::Min(15, $d)))
}

# Адский камень: тёмно-красный с вкраплениями
$hell = @(@(120, 40, 40, 4), @(104, 32, 34, 3), @(138, 52, 48, 2), @(80, 24, 26, 1), @(160, 70, 60, 0.5))
Save-Texture "Hellrock" { param($x, $y) Pick $hell }

# Обсидиан: почти чёрный с фиолетовыми искрами
$obsidian = @(@(26, 18, 38, 5), @(34, 24, 50, 3), @(18, 12, 26, 2), @(80, 50, 120, 0.4))
Save-Texture "Obsidian" { param($x, $y) Pick $obsidian }

# Сено: жёлтые волокна, через каждые 5 рядов тёмная перевязка
Save-Texture "Hay" {
    param($x, $y)
    if ($y -eq 4 -or $y -eq 11) { return @(140, 96, 40) }
    $d = $rng.Next(-14, 15)
    @((205 + $d), (172 + $d), (62 + [math]::Floor($d / 2)))
}

# Кактус: зелёный, тёмные полосы и светлые колючки
Save-Texture "Cactus" {
    param($x, $y)
    if ($x % 4 -eq 0) { return @(40, 96, 36) }
    if ($x % 4 -eq 2 -and $y % 4 -eq 1) { return @(220, 220, 170) }
    $d = $rng.Next(-8, 9)
    @((62 + $d), (132 + $d), (52 + $d))
}
