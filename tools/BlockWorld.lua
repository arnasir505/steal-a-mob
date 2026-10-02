-- Блочный декор всей карты: спавн и биомы, у каждого биома свой стиль.
--
-- Что строится:
--   Спавн  — холмы из блоков вокруг участков (с запасом под МАКСИМАЛЬНЫЙ рост участков),
--            деревья, цветы, фонари, тропинка к первому биому.
--   Биомы  — по бокам каждого биома холмы в его стиле, на них деревья и предметы;
--            внутри — земля в стиле биома, пятна (вода, лава, пашня...), трава и цветы
--            без столкновений, а твёрдые предметы — только у краёв (EDGE_BAND),
--            чтобы на большой скорости игрок ни во что не врезался посреди погони.
--            За последним биомом холмы закрывают конец карты.
--   Облака и невидимая стена по внешнему краю холмов (толщина 8).
--
-- Участки, SafeZone, биомы, ворота, точки яиц и боссов скрипт НЕ двигает и не меняет.
-- Возле точек яиц, ворот и босса предметы не ставятся (KEEP_CLEAR).
--
-- Что нужно в Workspace:
--   Plots                — участки (как для игры).
--   Biomes.<Имя>         — модель биома с деталью Area (объём биома). Имена стилей:
--                          Plains, Forest, Desert, Snow, Swamp, Nether, CrystalCave.
--                          Биома ещё нет в Config/Biomes — не страшно, декор всё равно встанет.
--
-- Как запустить: Studio -> View -> Command Bar -> вставить весь файл -> Enter.
-- Rojo должен быть подключён: скрипт читает GameConfig и Config/BlockTextures.
-- Повторный запуск удаляет модель WorldDecor и строит заново. Отмена: Ctrl+Z.
-- После запуска сохрани место (File -> Publish to Roblox).
--
-- Текстуры: Id картинок — в src/ReplicatedStorage/Shared/Config/BlockTextures.luau.

---------------------------------------------------------------- НАСТРОЙКИ
local B = 4                -- размер одного блока в студах
local MAX_RUN = 5          -- сколько одинаковых блоков подряд склеивать в одну деталь
local BARRIER_HEIGHT = 140 -- высота невидимой стены по внешнему краю
local MAX_LIGHTS = 120     -- сколько всего светящихся предметов с подсветкой (больше — тормозит)
local EXIT = "auto"        -- куда от спавна идут биомы: "auto", "+X", "-X", "+Z", "-Z"
local SEED = 7             -- поменяй число, чтобы холмы и предметы встали по-другому

-- Спавн
local SPAWN_MARGIN = 12    -- свободное место между участками (на максимуме) и холмами, студы
local SPAWN_ROWS = 8       -- глубина холмов спавна в блоках
local LANTERN_EVERY = 7    -- фонарь на краю холма через каждые N блоков (0 — без фонарей)
local PATH_WIDTH = 3       -- ширина тропинки к первому биому в блоках (0 — без тропинки)

-- Биомы
local BIOME_ROWS = 7       -- глубина холмов по бокам биома в блоках
local EDGE_BAND = 2        -- на сколько блоков от края биома внутрь можно ставить твёрдые предметы
local KEEP_CLEAR = 3       -- сколько блоков вокруг точек яиц, ворот и босса оставить пустыми
local GROUND_OVERLAY = true -- застелить пол биома землёй в его стиле
local CLOUDS = 30          -- сколько облаков над всей картой

---------------------------------------------------------------- ВИДЫ БЛОКОВ
-- Colors — оттенки (блоки рядом чуть отличаются). Texture — картинка из Config/BlockTextures.
-- Tint — подкраска картинки (только темнее). Neon — светится.
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local NEON = Enum.Material.Neon
local KINDS = {
	-- Земля
	GrassTop = { Texture = "GrassTop", Colors = { rgb(106, 164, 62), rgb(98, 154, 56), rgb(114, 172, 68) } },
	ForestGrass = { Texture = "GrassTop", Tint = rgb(190, 215, 180), Colors = { rgb(82, 140, 52), rgb(76, 132, 48) } },
	SwampGrass = { Texture = "GrassTop", Tint = rgb(150, 160, 105), Colors = { rgb(88, 104, 52), rgb(80, 96, 48) } },
	Dirt = { Texture = "Dirt", Colors = { rgb(134, 96, 67), rgb(124, 88, 61), rgb(142, 103, 72) } },
	Mud = { Texture = "Dirt", Tint = rgb(140, 120, 110), Colors = { rgb(92, 72, 56), rgb(84, 66, 52) } },
	CoarseDirt = { Texture = "Dirt", Tint = rgb(225, 215, 205), Colors = { rgb(120, 88, 62) } },
	Farmland = { Texture = "Dirt", Tint = rgb(120, 100, 90), Colors = { rgb(92, 64, 44) } },
	LeafLitter = { Texture = "Dirt", Tint = rgb(230, 175, 120), Colors = { rgb(128, 88, 46) } },
	Path = { Texture = "Path", Colors = { rgb(150, 120, 74), rgb(142, 112, 68) } },
	Sand = { Texture = "Sand", Colors = { rgb(219, 207, 160), rgb(212, 199, 150), rgb(225, 214, 168) } },
	RedSand = { Texture = "Sand", Tint = rgb(240, 170, 120), Colors = { rgb(190, 110, 60) } },
	Sandstone = { Texture = "Sandstone", Colors = { rgb(214, 196, 140), rgb(205, 188, 132) } },
	Snow = { Texture = "Snow", Colors = { rgb(245, 250, 252), rgb(236, 242, 248) } },
	Ice = { Texture = "Ice", Colors = { rgb(150, 190, 240), rgb(160, 200, 245) }, Transparency = 0.15, Reflectance = 0.2 },
	Stone = { Texture = "Stone", Colors = { rgb(125, 125, 125), rgb(116, 116, 116), rgb(133, 133, 133) } },
	DarkStone = { Texture = "Stone", Tint = rgb(95, 95, 115), Colors = { rgb(62, 62, 74), rgb(56, 56, 68) } },
	Basalt = { Texture = "Stone", Tint = rgb(75, 72, 80), Colors = { rgb(48, 46, 52) } },
	CrystalStone = { Texture = "Stone", Tint = rgb(160, 130, 200), Colors = { rgb(88, 70, 120) } },
	Ash = { Texture = "Stone", Tint = rgb(110, 100, 100), Colors = { rgb(70, 64, 64) } },
	Hellrock = { Texture = "Hellrock", Colors = { rgb(120, 40, 40), rgb(110, 34, 36), rgb(130, 46, 44) } },
	Obsidian = { Texture = "Obsidian", Colors = { rgb(30, 22, 44) } },
	StoneBrick = { Texture = "StoneBrick", Colors = { rgb(128, 128, 128) } },
	-- Деревья
	Log = { Texture = "Log", Colors = { rgb(102, 81, 51), rgb(94, 74, 46) } },
	DeadLog = { Texture = "Log", Tint = rgb(190, 180, 170), Colors = { rgb(110, 96, 80) } },
	BirchLog = { Texture = "BirchLog", Colors = { rgb(220, 218, 208) } },
	SpruceLog = { Texture = "Log", Tint = rgb(150, 140, 130), Colors = { rgb(70, 52, 34) } },
	FungusStem = { Texture = "Log", Tint = rgb(220, 120, 120), Colors = { rgb(120, 40, 40) } },
	Leaves = { Texture = "Leaves", Colors = { rgb(58, 122, 40), rgb(52, 112, 36), rgb(66, 132, 46) } },
	BirchLeaves = { Texture = "Leaves", Tint = rgb(225, 245, 190), Colors = { rgb(110, 160, 60), rgb(100, 150, 55) } },
	SpruceLeaves = { Texture = "Leaves", Tint = rgb(150, 175, 165), Colors = { rgb(40, 84, 44), rgb(36, 76, 40) } },
	SwampLeaves = { Texture = "Leaves", Tint = rgb(150, 165, 110), Colors = { rgb(70, 96, 40), rgb(64, 88, 36) } },
	Wart = { Texture = "Hellrock", Tint = rgb(255, 170, 170), Colors = { rgb(160, 24, 24), rgb(176, 32, 30) } },
	Vine = { Colors = { rgb(52, 92, 32), rgb(46, 84, 28) } },
	-- Растения и предметы
	Blade = { Colors = { rgb(92, 150, 52), rgb(104, 164, 60), rgb(84, 140, 46) } },
	DarkBlade = { Colors = { rgb(56, 104, 38), rgb(62, 112, 42) } },
	DryBlade = { Colors = { rgb(150, 116, 66), rgb(136, 104, 58) } },
	Wheat = { Colors = { rgb(220, 190, 80), rgb(206, 176, 70), rgb(190, 170, 70) } },
	Reed = { Colors = { rgb(100, 160, 64), rgb(90, 150, 58) } },
	Lily = { Colors = { rgb(40, 110, 40), rgb(50, 124, 46) } },
	Flower = { Colors = { rgb(220, 50, 50), rgb(250, 210, 40), rgb(80, 120, 230), rgb(245, 245, 245), rgb(240, 120, 190), rgb(250, 140, 40) } },
	Moss = { Colors = { rgb(80, 130, 50), rgb(72, 120, 46) } },
	Hay = { Texture = "Hay", Colors = { rgb(200, 170, 60) } },
	Pumpkin = { Colors = { rgb(220, 130, 30), rgb(208, 120, 26) } },
	Cactus = { Texture = "Cactus", Colors = { rgb(60, 130, 50), rgb(54, 122, 46) } },
	RedCap = { Colors = { rgb(200, 30, 30), rgb(186, 28, 28) } },
	BrownCap = { Colors = { rgb(150, 110, 80) } },
	MushroomStem = { Colors = { rgb(230, 225, 210) } },
	Bone = { Colors = { rgb(235, 232, 215) } },
	Carrot = { Colors = { rgb(240, 130, 30) } },
	Coal = { Colors = { rgb(30, 30, 30) } },
	Water = { Colors = { rgb(52, 112, 170) }, Transparency = 0.25, Reflectance = 0.15 },
	SwampWater = { Colors = { rgb(64, 92, 72), rgb(58, 86, 66) }, Transparency = 0.15, Reflectance = 0.1 },
	-- Светящееся
	Lamp = { Colors = { rgb(255, 214, 120) }, Material = NEON },
	Glow = { Colors = { rgb(255, 210, 110), rgb(250, 190, 90) }, Material = NEON },
	Lava = { Colors = { rgb(255, 110, 20), rgb(255, 135, 30) }, Material = NEON },
	Fire = { Colors = { rgb(255, 150, 40), rgb(255, 120, 30) }, Material = NEON },
	CrystalPink = { Colors = { rgb(255, 110, 200) }, Material = NEON },
	CrystalCyan = { Colors = { rgb(90, 230, 255) }, Material = NEON },
	CrystalPurple = { Colors = { rgb(170, 100, 255) }, Material = NEON },
	Cloud = { Colors = { rgb(255, 255, 255), rgb(245, 248, 255) } },
}
local CRYSTALS = { "CrystalPink", "CrystalCyan", "CrystalPurple" }
local CAP = 0.6 -- толщина верхнего слоя (трава, снег, песок) на холмах

---------------------------------------------------------------- СТИЛИ
-- Top/Fill/Deep — верх, слой под ним (FillDepth блоков) и глубина холмов.
-- Ground — чем застелить пол биома. Min/MaxHeight — высота холмов (в блоках).
-- Trees/TreeChance — деревья на холмах. HillPlants/HillProps — мелочь и предметы на холмах
-- (шанс на блок). Patches/PatchDensity — пятна на полу биома. Plants — трава на полу
-- (шанс на блок, без столкновений). EdgeProps/EdgeChance — твёрдые предметы у краёв биома.
local THEMES = {
	Spawn = {
		Top = "GrassTop", Fill = "Dirt", Deep = "Stone", MinHeight = 3, MaxHeight = 12,
		Trees = { Oak = 5, Birch = 2, Spruce = 3 }, TreeChance = 0.08,
		HillPlants = { Flower = 0.10, Tuft = 0.18 }, HillProps = { Bush = 0.03, Rock = 0.02 },
		Lanterns = true,
	},
	Plains = {
		Top = "GrassTop", Fill = "Dirt", Deep = "Stone", Ground = "GrassTop", MinHeight = 3, MaxHeight = 9,
		Trees = { Oak = 6, Birch = 1 }, TreeChance = 0.05,
		HillPlants = { Flower = 0.12, Tuft = 0.20 }, HillProps = { Bush = 0.03, HayBale = 0.02, Rock = 0.01 },
		Patches = { Farmland = 2, Path = 1 }, PatchDensity = 0.05,
		Plants = { Tuft = 0.06, Flower = 0.03 },
		EdgeProps = { HayBale = 3, Pumpkin = 2, Fence = 2 }, EdgeChance = 0.06,
	},
	Forest = {
		Top = "ForestGrass", Fill = "Dirt", Deep = "Stone", Ground = "ForestGrass", MinHeight = 4, MaxHeight = 12,
		Trees = { Oak = 4, Birch = 3, Spruce = 3 }, TreeChance = 0.16, TreeGap = 4,
		HillPlants = { Fern = 0.15, Tuft = 0.15, SmallMushroom = 0.03 },
		HillProps = { Bush = 0.04, MossyRock = 0.03, BigMushroom = 0.01 },
		Patches = { LeafLitter = 2, CoarseDirt = 1 }, PatchDensity = 0.08,
		Plants = { Fern = 0.06, DarkTuft = 0.06, SmallMushroom = 0.015 },
		EdgeProps = { Tree = 4, Stump = 2, BigMushroom = 1, FallenLog = 1, MossyRock = 1 }, EdgeChance = 0.10,
		EdgeBand = 3,
	},
	Desert = {
		Top = "Sand", Fill = "Sand", Deep = "Sandstone", FillDepth = 2, Ground = "Sand",
		MinHeight = 2, MaxHeight = 8, Bumps = 1.5,
		Trees = { DeadTree = 1 }, TreeChance = 0.015,
		HillPlants = { DeadBush = 0.06 }, HillProps = { Cactus = 0.05, Ruin = 0.006 },
		Patches = { RedSand = 2, SandstoneFloor = 1 }, PatchDensity = 0.06,
		Plants = { DeadBush = 0.015 },
		EdgeProps = { Cactus = 4, Ruin = 1, Fossil = 1 }, EdgeChance = 0.05,
	},
	Snow = {
		Top = "Snow", Fill = "Snow", Deep = "Stone", FillDepth = 1, Ground = "Snow", MinHeight = 4, MaxHeight = 14,
		Trees = { SnowySpruce = 1 }, TreeChance = 0.10,
		HillPlants = {}, HillProps = { IceSpike = 0.02, SnowRock = 0.03 },
		Patches = { Ice = 1 }, PatchDensity = 0.06,
		Plants = {},
		EdgeProps = { Snowman = 1, IceSpike = 2, SnowRock = 2, Tree = 2 }, EdgeChance = 0.05,
	},
	Swamp = {
		Top = "SwampGrass", Fill = "Mud", Deep = "Stone", Ground = "SwampGrass", MinHeight = 2, MaxHeight = 7,
		Trees = { SwampOak = 1 }, TreeChance = 0.08,
		HillPlants = { DarkTuft = 0.20, SmallMushroom = 0.04, Reed = 0.03 }, HillProps = { Bush = 0.04 },
		BushKind = "SwampLeaves",
		Patches = { SwampWater = 3, Mud = 1 }, PatchDensity = 0.14,
		Plants = { DarkTuft = 0.06, Reed = 0.015, SmallMushroom = 0.01 },
		EdgeProps = { Tree = 3, FallenLog = 2, Stump = 1 }, EdgeChance = 0.07,
	},
	Nether = {
		Top = "Hellrock", Fill = "Hellrock", Deep = "Basalt", FillDepth = 4, Ground = "Hellrock",
		MinHeight = 4, MaxHeight = 14,
		Trees = { Fungus = 1 }, TreeChance = 0.05,
		HillPlants = { Fire = 0.03, SmallMushroom = 0.02 }, HillProps = { GlowRock = 0.02, LavaPool = 0.04 },
		Patches = { Lava = 1, Ash = 2 }, PatchDensity = 0.07,
		Plants = { Fire = 0.01 },
		EdgeProps = { ObsidianPillar = 2, GlowRock = 2, Tree = 1 }, EdgeChance = 0.05,
	},
	CrystalCave = {
		Top = "DarkStone", Fill = "DarkStone", Deep = "Basalt", FillDepth = 4, Ground = "DarkStone",
		MinHeight = 6, MaxHeight = 18, Bumps = 3,
		Trees = {}, TreeChance = 0,
		HillPlants = { SmallCrystal = 0.04 }, HillProps = { Crystal = 0.04, Stalagmite = 0.04 },
		Patches = { CrystalFloor = 1 }, PatchDensity = 0.06,
		Plants = { SmallCrystal = 0.012 },
		EdgeProps = { Crystal = 2, Stalagmite = 3 }, EdgeChance = 0.07,
	},
}

-- Пятна на полу биома: из чего и какого размера (в блоках), что на них растёт
local PATCHES = {
	Farmland = { Kind = "Farmland", Size = { 8, 20 }, Plants = { Wheat = 0.85 } },
	Path = { Kind = "Path", Size = { 5, 14 } },
	LeafLitter = { Kind = "LeafLitter", Size = { 6, 16 } },
	CoarseDirt = { Kind = "CoarseDirt", Size = { 4, 12 } },
	RedSand = { Kind = "RedSand", Size = { 8, 24 } },
	SandstoneFloor = { Kind = "Sandstone", Size = { 4, 10 } },
	Ice = { Kind = "Ice", Size = { 8, 24 } },
	SwampWater = { Kind = "SwampWater", Size = { 10, 30 }, Plants = { LilyPad = 0.15 } },
	Mud = { Kind = "Mud", Size = { 5, 14 } },
	Lava = { Kind = "Lava", Size = { 3, 9 }, Glow = true },
	Ash = { Kind = "Ash", Size = { 6, 16 } },
	CrystalFloor = { Kind = "CrystalStone", Size = { 6, 16 }, Plants = { SmallCrystal = 0.15 } },
}

---------------------------------------------------------------- ПОМОЩНИКИ
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local rng = Random.new(SEED)
local partCount = 0
local lightsUsed = 0

local function tryRequire(names)
	local node = ReplicatedStorage
	for _, name in ipairs(names) do
		node = node and node:FindFirstChild(name)
	end
	if not node then
		return nil
	end
	local ok, result = pcall(require, node)
	return ok and result or nil
end

local TEXTURES = tryRequire({ "Shared", "Config", "BlockTextures" }) or {}

-- Деталь из модели или сама деталь
local function resolvePart(holder)
	if not holder then
		return nil
	end
	if holder:IsA("BasePart") then
		return holder
	end
	if holder:IsA("Model") then
		return holder.PrimaryPart or holder:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Габарит: CFrame центра и размер
local function boxOf(instance)
	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end
	local ok, cframe, size = pcall(function()
		return instance:GetBoundingBox()
	end)
	if ok then
		return cframe, size
	end
	return CFrame.new(), Vector3.zero
end

local function key(i, j)
	return i .. "," .. j
end

-- Случайный ключ по весам (ключи сортируем, чтобы с тем же SEED результат был тот же)
local function sortedKeys(map)
	local keys = {}
	for k in pairs(map or {}) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end
local function pickWeighted(weights)
	local keys = sortedKeys(weights)
	local total = 0
	for _, k in ipairs(keys) do
		total += weights[k]
	end
	local roll = rng:NextNumber() * total
	for _, k in ipairs(keys) do
		roll -= weights[k]
		if roll <= 0 then
			return k
		end
	end
	return keys[1]
end
-- Шансы на блок: вернёт выпавшее имя или nil
local function rollChances(chances)
	local roll = rng:NextNumber()
	for _, k in ipairs(sortedKeys(chances)) do
		roll -= chances[k]
		if roll < 0 then
			return k
		end
	end
	return nil
end

---------------------------------------------------------------- ГДЕ УЧАСТКИ И БИОМЫ
local plotsFolder = workspace:FindFirstChild("Plots")
if not plotsFolder then
	warn("[BlockWorld] В Workspace нет папки Plots. Сначала расставь участки Plot1..Plot7, потом запускай.")
	return
end

local GameConfig = tryRequire({ "Shared", "Config", "GameConfig" })
local Formulas = tryRequire({ "Shared", "Formulas" })
if not GameConfig or not Formulas then
	warn("[BlockWorld] Не прочитался GameConfig (Rojo подключён?). Считаю рост участков по умолчанию.")
end
local P = GameConfig and GameConfig.Plot or {}

-- Шаг роста = длина звена забора уровня 0, как в PlotBuilder
local function growStep()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fences = assets and assets:FindFirstChild("Fences")
	local best, bestLevel
	for _, child in ipairs(fences and fences:GetChildren() or {}) do
		if child:IsA("Model") or child:IsA("BasePart") then
			local _, size = boxOf(child)
			local length = math.max(size.X, size.Z)
			local level = tonumber(string.match(child.Name, "(%d+)$")) or 0
			if length >= 1 and (not best or level < bestLevel) then
				best, bestLevel = length, level
			end
		end
	end
	return best or P.GrowStep or 4
end

local maxLevel = math.min(P.GrowMaxLevel or 10, Formulas and Formulas.MaxBaseLevel() or 10)
local step = growStep()
local growSide = maxLevel * (P.GrowSideSegments or 1) * step
local growDepth = maxLevel * (P.GrowDepthSegments or 1) * step

-- Точки, которые должны поместиться внутри спавна: участки на максимуме и всё у них снаружи пола
local spawnPoints = {}
local groundY = math.huge
local plotCount = 0
for _, plot in ipairs(plotsFolder:GetChildren()) do
	local floor = plot:FindFirstChild("Floor", true)
	if floor and floor:IsA("BasePart") then
		plotCount += 1
		local cf = floor.CFrame
		local hx, hz = floor.Size.X / 2, floor.Size.Z / 2
		-- Вход участка — сторона пола, ближайшая к Spawn (как в PlotBuilder)
		local angle = 0
		local marker = resolvePart(plot:FindFirstChild("Spawn", true)) or resolvePart(plot:FindFirstChild("Sign", true))
		if marker then
			local p = cf:PointToObjectSpace(marker.Position)
			if math.abs(p.X) / hx > math.abs(p.Z) / hz then
				angle = p.X > 0 and 90 or -90
			else
				angle = p.Z >= 0 and 0 or 180
			end
		end
		if angle == 90 or angle == -90 then
			hx, hz = hz, hx
		end
		local frame = cf * CFrame.Angles(0, math.rad(angle), 0)
		for _, corner in ipairs({
			{ -hx - growSide, -hz - growDepth },
			{ hx + growSide, -hz - growDepth },
			{ -hx - growSide, hz },
			{ hx + growSide, hz },
		}) do
			table.insert(spawnPoints, { frame:PointToWorldSpace(Vector3.new(corner[1], 0, corner[2])), 0 })
		end
		for _, d in ipairs(plot:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(spawnPoints, { d.Position, 2 })
			end
		end
		groundY = math.min(groundY, floor.Position.Y - floor.Size.Y / 2)
	end
end
if plotCount == 0 then
	warn("[BlockWorld] В Workspace.Plots нет участков с деталью Floor.")
	return
end

local spawnCenter = Vector3.zero
for _, item in ipairs(spawnPoints) do
	spawnCenter += item[1]
end
spawnCenter /= #spawnPoints

-- Модели биомов
local biomeModels = {}
local biomesFolder = workspace:FindFirstChild("Biomes")
for _, model in ipairs(biomesFolder and biomesFolder:GetChildren() or {}) do
	if model:IsA("PVInstance") then
		table.insert(biomeModels, model)
	end
end

---------------------------------------------------------------- ОСИ КАРТЫ
-- Свои оси: v (+Z) — от спавна к биомам, u (X) — поперёк. Сетка блоков общая для всей
-- карты, поэтому холмы соседних биомов и спавна встают вплотную, без нахлёста.
local AXES = { ["+X"] = Vector3.xAxis, ["-X"] = -Vector3.xAxis, ["+Z"] = Vector3.zAxis, ["-Z"] = -Vector3.zAxis }
local exitName = EXIT
local exitDir = AXES[EXIT]
if not exitDir then
	local sum = Vector3.zero
	for _, model in ipairs(biomeModels) do
		sum += model:GetPivot().Position
	end
	local d = #biomeModels > 0 and (sum / #biomeModels - spawnCenter) or Vector3.zero
	if d.Magnitude < 1 then
		warn("[BlockWorld] Не нашёл Workspace.Biomes — считаю, что биомы в стороне +Z. Поменяй EXIT, если надо.")
		d = Vector3.zAxis
	end
	if math.abs(d.X) > math.abs(d.Z) then
		exitName = d.X > 0 and "+X" or "-X"
	else
		exitName = d.Z > 0 and "+Z" or "-Z"
	end
	exitDir = AXES[exitName]
end
local G = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis:Cross(exitDir), Vector3.yAxis, exitDir)

local function at(u, y, v)
	return G * CFrame.new(u, y, v)
end
local function toUV(point)
	local p = G:PointToObjectSpace(point)
	return p.X, p.Z
end
-- Прямоугольник детали/модели в осях карты
local function rectOf(instance)
	local cf, size = boxOf(instance)
	local u0, u1, v0, v1 = math.huge, -math.huge, math.huge, -math.huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local u, v = toUV(cf:PointToWorldSpace(Vector3.new(sx * size.X / 2, 0, sz * size.Z / 2)))
			u0, u1, v0, v1 = math.min(u0, u), math.max(u1, u), math.min(v0, v), math.max(v1, v)
		end
	end
	return u0, u1, v0, v1, cf, size
end
local function cellOf(u, v)
	return math.floor(u / B), math.floor(v / B)
end
local function roundCell(x)
	return math.floor(x / B + 0.5)
end

---------------------------------------------------------------- ПОДГОТОВКА
for _, name in ipairs({ "WorldDecor", "SpawnDecor" }) do
	local old = workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
if workspace:FindFirstChild("MinecraftSpawn") then
	warn("[BlockWorld] В Workspace осталась модель MinecraftSpawn от старого скрипта — удали её.")
end
ChangeHistoryService:SetWaypoint("Before WorldDecor")

local root = Instance.new("Model")
root.Name = "WorldDecor"
local folders = {}
local function folderOf(regionName, name)
	local k = regionName .. "/" .. name
	if not folders[k] then
		local parent = folders[regionName]
		if not parent then
			parent = Instance.new("Folder")
			parent.Name = regionName
			parent.Parent = root
			folders[regionName] = parent
		end
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
		folders[k] = f
	end
	return folders[k]
end

---------------------------------------------------------------- ДЕТАЛИ
local ALL_SIDES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }
local TOP_ONLY = { Enum.NormalId.Top }
local SIDES_ONLY = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }

local function block(parent, name, kind, size, cframe, faces)
	local info = KINDS[kind]
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = info.Colors[rng:NextInteger(1, #info.Colors)]
	p.Material = info.Material or Enum.Material.SmoothPlastic
	p.Transparency = info.Transparency or 0
	p.Reflectance = info.Reflectance or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local id = info.Texture and TEXTURES[info.Texture]
	if id and id ~= 0 then
		-- Одна плитка текстуры = один блок, поэтому склеенные блоки всё равно видны по отдельности
		for _, face in ipairs(faces or ALL_SIDES) do
			local t = Instance.new("Texture")
			t.Texture = "rbxassetid://" .. id
			t.Face = face
			t.StudsPerTileU = B
			t.StudsPerTileV = B
			t.Color3 = info.Tint or Color3.new(1, 1, 1)
			t.Transparency = info.Transparency or 0
			t.Parent = p
		end
	end
	p.Parent = parent
	partCount += 1
	return p
end

-- Коробка: u, v — центр, y — низ, размеры в студах
local function box(parent, kind, u, y, v, su, sy, sv, faces)
	return block(parent, kind, kind, Vector3.new(su, sy, sv), at(u, y + sy / 2, v), faces)
end

-- Мелочь без столкновений: игроки и камера сквозь неё проходят
local function decor(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- Подсветка (не больше MAX_LIGHTS на всю карту)
local function glow(part, range, brightness)
	if lightsUsed >= MAX_LIGHTS then
		return
	end
	lightsUsed += 1
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = part.Color
	light.Parent = part
end

---------------------------------------------------------------- ДЕРЕВЬЯ
local TREE_KINDS = {
	Oak = { Log = "Log", Leaves = "Leaves", Trunk = { 4, 6 }, Shape = "Round" },
	Birch = { Log = "BirchLog", Leaves = "BirchLeaves", Trunk = { 5, 7 }, Shape = "Round" },
	Spruce = { Log = "SpruceLog", Leaves = "SpruceLeaves", Trunk = { 6, 8 }, Shape = "Cone" },
	SnowySpruce = { Log = "SpruceLog", Leaves = "SpruceLeaves", Trunk = { 6, 8 }, Shape = "Cone", Snow = true },
	SwampOak = { Log = "Log", Leaves = "SwampLeaves", Trunk = { 4, 6 }, Shape = "Round", Vines = true },
	Fungus = { Log = "FungusStem", Leaves = "Wart", Trunk = { 4, 7 }, Shape = "Cap" },
	DeadTree = { Log = "DeadLog", Trunk = { 3, 5 }, Shape = "Dead" },
}

-- Формы слоёв листвы: { du, dv, su, sv } в блоках
local LAYERS = {
	[5] = { { 0, 0, 5, 3 }, { 0, -2, 3, 1 }, { 0, 2, 3, 1 } }, -- 5x5 без углов
	[3] = { { 0, 0, 3, 3 } },
	plus = { { 0, 0, 3, 1 }, { 0, -1, 1, 1 }, { 0, 1, 1, 1 } },
	[1] = { { 0, 0, 1, 1 } },
}

local function tree(kindName, parent, cu, cv, groundTop)
	local kind = TREE_KINDS[kindName]
	local m = Instance.new("Model")
	m.Name = kindName .. "Tree"
	m.Parent = parent
	local trunk = rng:NextInteger(kind.Trunk[1], kind.Trunk[2])

	-- Коробка в блоках от основания ствола: du/dv — центр, y — низ, su/sy/sv — размер
	local function cell(blockKind, du, y, dv, su, sy, sv, noCollide)
		local p = block(m, blockKind, blockKind, Vector3.new(su * B, sy * B, sv * B),
			at(cu + du * B, groundTop + (y + sy / 2) * B, cv + dv * B))
		if noCollide or blockKind == kind.Leaves then
			p.CanCollide = false
		end
		return p
	end
	local function layer(y, shape, sy)
		for _, r in ipairs(LAYERS[shape]) do
			cell(kind.Leaves, r[1], y, r[2], r[3], sy, r[4])
			if kind.Snow then
				-- Снежная шапка на слое
				decor(block(m, "Snow", "Snow", Vector3.new(r[3] * B, 0.4, r[4] * B),
					at(cu + r[1] * B, groundTop + (y + sy) * B + 0.2, cv + r[2] * B)))
			end
		end
	end
	local function corners(y, offset, sy, chance)
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			if rng:NextNumber() < chance then
				cell(kind.Leaves, c[1] * offset, y, c[2] * offset, 1, sy, 1)
			end
		end
	end

	cell(kind.Log, 0, 0, 0, 1, trunk, 1)

	if kind.Shape == "Cone" then
		local y = 2
		for _, shape in ipairs({ 5, 3, 5, 3 }) do
			if y >= trunk - 1 then
				break
			end
			layer(y, shape, 1)
			y += 1
		end
		for yy = y, trunk - 1 do
			layer(yy, 3, 1)
		end
		layer(trunk, "plus", 1)
		layer(trunk + 1, 1, 1)
	elseif kind.Shape == "Round" then
		local low = trunk - 3
		layer(low, 5, 2)
		corners(low, 2, 1, 0.5)
		corners(low + 1, 2, 1, 0.3)
		layer(trunk - 1, "plus", 1)
		corners(trunk - 1, 1, 1, 0.5)
		layer(trunk, "plus", 1)
		if kind.Vines then
			-- Лианы свисают с краёв нижнего слоя
			for _, s in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				for k = -1, 1 do
					if rng:NextNumber() < 0.35 then
						local length = rng:NextInteger(2, 4) * B
						local du = s[1] ~= 0 and s[1] * (2.5 * B + 0.15) or k * B
						local dv = s[2] ~= 0 and s[2] * (2.5 * B + 0.15) or k * B
						local size = s[1] ~= 0 and Vector3.new(0.3, length, B * 0.8) or Vector3.new(B * 0.8, length, 0.3)
						decor(block(m, "Vine", "Vine", size, at(cu + du, groundTop + (low + 2) * B - length / 2, cv + dv)))
					end
				end
			end
		end
	elseif kind.Shape == "Cap" then
		-- Гриб-дерево: широкая шляпка, снизу свисают кусочки, внутри светится
		layer(trunk, 5, 1)
		corners(trunk, 2, 1, 0.5)
		layer(trunk + 1, 3, 1)
		for _ = 1, rng:NextInteger(2, 4) do
			local du, dv = rng:NextInteger(-2, 2), rng:NextInteger(-2, 2)
			if math.abs(du) == 2 or math.abs(dv) == 2 then
				decor(cell(kind.Leaves, du, trunk - 1, dv, 1, 1, 1))
			end
		end
		local light = cell("Glow", rng:NextInteger(-1, 1), trunk - 0.5, 1, 0.5, 0.5, 0.5, true)
		glow(light, 16, 1)
	else -- Dead: сухое дерево с двумя ветками
		for _, s in ipairs({ 1, -1 }) do
			local alongU = rng:NextNumber() < 0.5
			local y = trunk - rng:NextInteger(1, 2)
			local du, dv = alongU and s * 1 or 0, alongU and 0 or s * 1
			cell(kind.Log, du, y, dv, alongU and 1 or 0.6, 0.6, alongU and 0.6 or 1)
			cell(kind.Log, du * 1.5, y + 0.6, dv * 1.5, 0.6, 1, 0.6)
		end
	end
end

---------------------------------------------------------------- РАСТЕНИЯ (без столкновений)
local function crossed(parent, kind, u, y, v, w, h, extraAngle)
	for _, a in ipairs({ 45, -45 }) do
		decor(block(parent, kind, kind, Vector3.new(w, h, 0.15),
			at(u, y + h / 2, v) * CFrame.Angles(0, math.rad(a + (extraAngle or 0)), 0)))
	end
end

local PLANTS = {
	Tuft = function(p, u, y, v)
		crossed(p, "Blade", u, y, v, 2.2, 1.6)
	end,
	DarkTuft = function(p, u, y, v)
		crossed(p, "DarkBlade", u, y, v, 2.2, 1.8)
	end,
	Fern = function(p, u, y, v)
		crossed(p, "DarkBlade", u, y, v, 2.6, 2.0)
		crossed(p, "DarkBlade", u, y, v, 2.2, 1.6, 45)
	end,
	DeadBush = function(p, u, y, v)
		crossed(p, "DryBlade", u, y, v, 2.4, 1.8)
	end,
	Wheat = function(p, u, y, v)
		crossed(p, "Wheat", u, y, v, 2.6, 2.6)
		crossed(p, "Wheat", u, y, v, 2.2, 2.2, 22)
	end,
	Flower = function(p, u, y, v)
		decor(box(p, "Blade", u, y, v, 0.3, 1.4, 0.3))
		decor(box(p, "Flower", u, y + 1.3, v, 0.9, 0.9, 0.9))
	end,
	Reed = function(p, u, y, v)
		for _ = 1, rng:NextInteger(1, 3) do
			local du, dv = rng:NextNumber(-0.8, 0.8), rng:NextNumber(-0.8, 0.8)
			decor(box(p, "Reed", u + du, y, v + dv, 0.5, rng:NextInteger(4, 8), 0.5))
		end
	end,
	SmallMushroom = function(p, u, y, v)
		decor(box(p, "MushroomStem", u, y, v, 0.35, 0.7, 0.35))
		decor(box(p, rng:NextNumber() < 0.5 and "RedCap" or "BrownCap", u, y + 0.7, v, 1.1, 0.4, 1.1))
	end,
	LilyPad = function(p, u, y, v)
		decor(block(p, "Lily", "Lily", Vector3.new(2.4, 0.1, 2.4),
			at(u, y + 0.12, v) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0)))
	end,
	Fire = function(p, u, y, v)
		crossed(p, "Fire", u, y, v, 1.8, 2.0)
	end,
	SmallCrystal = function(p, u, y, v)
		local h = rng:NextNumber(1.2, 2.6)
		local part = decor(block(p, "Crystal", CRYSTALS[rng:NextInteger(1, #CRYSTALS)], Vector3.new(0.7, h, 0.7),
			at(u, y + h / 2 - 0.1, v) * CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), 0, math.rad(rng:NextNumber(-20, 20)))))
		if rng:NextNumber() < 0.15 then
			glow(part, 10, 0.8)
		end
	end,
}

---------------------------------------------------------------- ПРЕДМЕТЫ (твёрдые)
-- c = { Parent, U, V, Y (верх земли), Inward (+1/-1 — в какую сторону по u середина), Theme }
local PROPS = {}
PROPS.Bush = function(c)
	box(c.Parent, c.Theme.BushKind or "Leaves", c.U, c.Y, c.V, B, B, B)
end
PROPS.Rock = function(c)
	box(c.Parent, "Stone", c.U, c.Y, c.V, B, B * 0.75, B)
	box(c.Parent, "Stone", c.U + B * 0.4, c.Y + B * 0.75, c.V - B * 0.2, B / 2, B / 2, B / 2)
end
PROPS.MossyRock = function(c)
	PROPS.Rock(c)
	decor(box(c.Parent, "Moss", c.U, c.Y + B * 0.75, c.V, B, 0.3, B))
end
PROPS.SnowRock = function(c)
	box(c.Parent, "Stone", c.U, c.Y, c.V, B, B * 0.75, B)
	decor(box(c.Parent, "Snow", c.U, c.Y + B * 0.75, c.V, B, 0.4, B))
end
PROPS.HayBale = function(c)
	box(c.Parent, "Hay", c.U, c.Y, c.V, B, B, B)
	if rng:NextNumber() < 0.3 then
		box(c.Parent, "Hay", c.U, c.Y + B, c.V, B, B, B)
	end
end
PROPS.Pumpkin = function(c)
	box(c.Parent, "Pumpkin", c.U, c.Y, c.V, B * 0.8, B * 0.7, B * 0.8)
	decor(box(c.Parent, "Log", c.U, c.Y + B * 0.7, c.V, 0.4, 0.8, 0.4))
end
PROPS.Fence = function(c)
	-- Кусок деревянного забора вдоль края биома
	for k = -1, 1 do
		box(c.Parent, "Log", c.U, c.Y, c.V + k * B, 0.8, B * 1.2, 0.8)
	end
	for _, h in ipairs({ B * 0.45, B * 0.95 }) do
		box(c.Parent, "Log", c.U, c.Y + h, c.V, 0.4, 0.4, 2 * B)
	end
end
PROPS.Stump = function(c)
	box(c.Parent, "Log", c.U, c.Y, c.V, B, B * 0.6, B)
end
PROPS.FallenLog = function(c)
	box(c.Parent, "Log", c.U, c.Y, c.V, B, B, 3 * B)
	decor(box(c.Parent, "Moss", c.U, c.Y + B, c.V + rng:NextNumber(-B, B), B, 0.3, B))
end
PROPS.BigMushroom = function(c)
	local h = rng:NextInteger(2, 3) * B
	box(c.Parent, "MushroomStem", c.U, c.Y, c.V, 1.4, h, 1.4)
	box(c.Parent, rng:NextNumber() < 0.7 and "RedCap" or "BrownCap", c.U, c.Y + h, c.V, 3 * B, B * 0.75, 3 * B)
end
PROPS.Cactus = function(c)
	local h = rng:NextInteger(1, 3) * B
	local w = B * 0.875
	box(c.Parent, "Cactus", c.U, c.Y, c.V, w, h, w)
	if h > B and rng:NextNumber() < 0.4 then
		local s = rng:NextNumber() < 0.5 and 1 or -1
		box(c.Parent, "Cactus", c.U, c.Y + h * 0.45, c.V + s * B * 0.7, w * 0.5, w * 0.5, B * 0.6)
		box(c.Parent, "Cactus", c.U, c.Y + h * 0.45, c.V + s * B * 0.85, w * 0.5, B * 0.8, w * 0.5)
	end
end
PROPS.Ruin = function(c)
	-- Обломок колонны из песчаника и упавший блок рядом
	local h = rng:NextInteger(2, 4) * B
	box(c.Parent, "Sandstone", c.U, c.Y, c.V, B, h, B)
	block(c.Parent, "Sandstone", "Sandstone", Vector3.new(B, B * 0.6, B),
		at(c.U, c.Y + h + B * 0.25, c.V) * CFrame.Angles(0, math.rad(rng:NextNumber(10, 30)), math.rad(rng:NextNumber(5, 15))))
	box(c.Parent, "Sandstone", c.U, c.Y, c.V + B * 1.2, B, B * 0.6, B)
end
PROPS.Fossil = function(c)
	-- Рёбра древнего скелета, наполовину в песке
	box(c.Parent, "Bone", c.U, c.Y + B * 1.6, c.V, 0.6, 0.6, 3 * B)
	for k = -1, 1 do
		for _, s in ipairs({ -1, 1 }) do
			block(c.Parent, "Bone", "Bone", Vector3.new(0.5, B * 1.8, 0.5),
				at(c.U + s * B * 0.5, c.Y + B * 0.8, c.V + k * B) * CFrame.Angles(0, 0, math.rad(s * 18)))
		end
	end
end
PROPS.Snowman = function(c)
	box(c.Parent, "Snow", c.U, c.Y, c.V, B, B, B)
	box(c.Parent, "Snow", c.U, c.Y + B, c.V, B * 0.75, B * 0.75, B * 0.75)
	local headY = c.Y + B * 1.75
	box(c.Parent, "Snow", c.U, headY, c.V, B * 0.55, B * 0.55, B * 0.55)
	local face = c.U + c.Inward * B * 0.28
	decor(box(c.Parent, "Carrot", face + c.Inward * 0.4, headY + B * 0.22, c.V, 0.8, 0.3, 0.3))
	for _, s in ipairs({ -1, 1 }) do
		decor(box(c.Parent, "Coal", face, headY + B * 0.36, c.V + s * 0.5, 0.25, 0.25, 0.25))
	end
end
PROPS.IceSpike = function(c)
	local h = rng:NextInteger(3, 7) * B
	box(c.Parent, "Ice", c.U, c.Y, c.V, B, h, B)
	box(c.Parent, "Ice", c.U, c.Y + h, c.V, B * 0.5, B * 1.5, B * 0.5)
end
PROPS.GlowRock = function(c)
	glow(box(c.Parent, "Glow", c.U, c.Y, c.V, B, B, B), 18, 1.2)
end
PROPS.LavaPool = function(c)
	glow(decor(box(c.Parent, "Lava", c.U, c.Y - 0.05, c.V, B, 0.2, B)), 14, 1)
end
PROPS.ObsidianPillar = function(c)
	box(c.Parent, "Obsidian", c.U, c.Y, c.V, B, rng:NextInteger(2, 5) * B, B)
end
PROPS.Stalagmite = function(c)
	box(c.Parent, "DarkStone", c.U, c.Y, c.V, B, B, B)
	box(c.Parent, "DarkStone", c.U, c.Y + B, c.V, B * 0.6, B * 0.9, B * 0.6)
	box(c.Parent, "DarkStone", c.U, c.Y + B * 1.9, c.V, B * 0.3, B * 0.8, B * 0.3)
end
PROPS.Crystal = function(c)
	local kind = CRYSTALS[rng:NextInteger(1, #CRYSTALS)]
	for k = 1, 3 do
		local h = rng:NextNumber(1, 2.6) * B
		local part = block(c.Parent, "Crystal", kind, Vector3.new(1.4, h, 1.4),
			at(c.U + rng:NextNumber(-1, 1), c.Y + h / 2 - 0.3, c.V + rng:NextNumber(-1, 1))
				* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), 0, math.rad(rng:NextNumber(-25, 25))))
		if k == 1 then
			glow(part, 18, 1.2)
		end
	end
end
PROPS.Tree = function(c)
	if c.Theme.Trees and next(c.Theme.Trees) then
		tree(pickWeighted(c.Theme.Trees), c.Parent, c.U, c.V, c.Y)
	end
end

---------------------------------------------------------------- ОБЛАСТИ: СПАВН И БИОМЫ
-- У каждой области: прямоугольник клеток внутри (I0..I1, J0..J1), высота пола, стиль.
local regions = {}
local interior = {} -- клетки внутри спавна и биомов: туда холмы не ставятся

local su0, su1, sv0, sv1 = math.huge, -math.huge, math.huge, -math.huge
for _, item in ipairs(spawnPoints) do
	local u, v = toUV(item[1])
	su0, su1 = math.min(su0, u - item[2]), math.max(su1, u + item[2])
	sv0, sv1 = math.min(sv0, v - item[2]), math.max(sv1, v + item[2])
end
local spawnRegion = {
	Name = "Spawn",
	Theme = THEMES.Spawn,
	I0 = math.floor((su0 - SPAWN_MARGIN) / B), I1 = math.ceil((su1 + SPAWN_MARGIN) / B) - 1,
	J0 = math.floor((sv0 - SPAWN_MARGIN) / B), J1 = math.ceil((sv1 + SPAWN_MARGIN) / B) - 1,
	Y = groundY,
	Rows = SPAWN_ROWS,
	IsSpawn = true,
}

-- Пол биома: несколько лучей сверху вниз, берём средний результат
local function findFloor(model, areaPart, areaCf, areaSize)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	if areaPart then
		table.insert(ignore, areaPart)
	end
	for _, name in ipairs({ "Gate", "EggSpawns", "BossSpawn" }) do
		local found = model:FindFirstChild(name, true)
		if found then
			table.insert(ignore, found)
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Humanoid") and d.Parent then
			table.insert(ignore, d.Parent)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hits = {}
	local top = areaCf.Position.Y + areaSize.Y / 2 + 50
	for _, offset in ipairs({ { 0, 0 }, { 0.25, 0.25 }, { -0.25, 0.25 }, { 0.25, -0.25 }, { -0.25, -0.25 } }) do
		local p = areaCf:PointToWorldSpace(Vector3.new(offset[1] * areaSize.X, 0, offset[2] * areaSize.Z))
		local result = workspace:Raycast(Vector3.new(p.X, top, p.Z), Vector3.new(0, -(areaSize.Y + 400), 0), params)
		if result then
			table.insert(hits, result.Position.Y)
		end
	end
	if #hits == 0 then
		return areaCf.Position.Y - areaSize.Y / 2
	end
	table.sort(hits)
	return hits[math.ceil(#hits / 2)]
end

local missingThemes = {}
for _, model in ipairs(biomeModels) do
	local themeName = string.gsub(model.Name, "%s", "")
	local theme = THEMES[themeName]
	if not theme or themeName == "Spawn" then
		table.insert(missingThemes, model.Name)
		theme = THEMES.Plains
	end
	local area = model:FindFirstChild("Area", true)
	local areaPart = (area and area:IsA("BasePart")) and area or nil
	if not areaPart then
		warn("[BlockWorld] У биома " .. model.Name .. " нет детали Area — границы взяты по всей модели.")
	end
	local u0, u1, v0, v1, cf, size = rectOf(areaPart or model)
	local region = {
		Name = model.Name,
		Model = model,
		Theme = theme,
		I0 = roundCell(u0), I1 = roundCell(u1) - 1,
		J0 = roundCell(v0), J1 = roundCell(v1) - 1,
		Y = findFloor(model, areaPart, cf, size),
		Rows = BIOME_ROWS,
	}
	if region.I1 >= region.I0 and region.J1 >= region.J0 then
		table.insert(regions, region)
	end
end
-- Биомы по порядку от спавна
table.sort(regions, function(a, b)
	return a.J0 < b.J0
end)
for index, region in ipairs(regions) do
	local nextRegion = regions[index + 1]
	-- Холмы по бокам тянутся до следующего биома; за последним — закрывают конец карты
	region.HillJ1 = nextRegion and math.max(region.J1, nextRegion.J0 - 1) or (region.J1 + region.Rows)
	region.IsLast = nextRegion == nil
end

for _, region in ipairs({ spawnRegion, table.unpack(regions) }) do
	for i = region.I0, region.I1 do
		for j = region.J0, region.J1 do
			interior[key(i, j)] = region
		end
	end
end

---------------------------------------------------------------- ХОЛМЫ: КАКАЯ КЛЕТКА ЧЬЯ
local hills = {} -- [key] = { H, Y, Theme, R, Rows, Region, Inward }
local minI, maxI, minJ, maxJ = math.huge, -math.huge, math.huge, -math.huge

local function assign(region, i, j, r)
	local k = key(i, j)
	if r <= 0 or r > region.Rows or interior[k] or hills[k] then
		return
	end
	local theme = region.Theme
	local t = region.Rows > 1 and (r - 1) / (region.Rows - 1) or 1
	local h = theme.MinHeight + t * (theme.MaxHeight - theme.MinHeight)
		+ math.noise(i * 0.17, j * 0.17, SEED + 0.5) * (theme.Bumps or 2) * 2
	hills[k] = {
		H = math.max(theme.MinHeight, math.floor(h + 0.5)),
		Y = region.Y,
		Theme = theme,
		R = r,
		Rows = region.Rows,
		Region = region,
		Inward = i < (region.I0 + region.I1) / 2 and 1 or -1,
	}
	minI, maxI = math.min(minI, i), math.max(maxI, i)
	minJ, maxJ = math.min(minJ, j), math.max(maxJ, j)
end

local function sideDistance(region, i)
	if i < region.I0 then
		return region.I0 - i
	elseif i > region.I1 then
		return i - region.I1
	end
	return 0
end

-- Сначала биомы (их бока — в их стиле), потом спавн со всех 4 сторон
for _, region in ipairs(regions) do
	for j = region.J0, region.HillJ1 do
		for i = region.I0 - region.Rows, region.I1 + region.Rows do
			local du = sideDistance(region, i)
			local dv = region.IsLast and math.max(0, j - region.J1) or 0
			assign(region, i, j, math.max(du, dv))
		end
	end
end
do
	local s = spawnRegion
	for j = s.J0 - s.Rows, s.J1 + s.Rows do
		for i = s.I0 - s.Rows, s.I1 + s.Rows do
			local dv = 0
			if j < s.J0 then
				dv = s.J0 - j
			elseif j > s.J1 then
				dv = j - s.J1
			end
			assign(s, i, j, math.max(sideDistance(s, i), dv))
		end
	end
end

---------------------------------------------------------------- ХОЛМЫ: СТРОИМ
-- Столбик (или несколько одинаковых подряд): верхний слой, FillDepth блоков, ниже Deep
local function column(parent, theme, baseY, h, u, v, sizeU)
	local top = baseY + h * B
	block(parent, theme.Top, theme.Top, Vector3.new(sizeU, CAP, B), at(u, top + CAP / 2, v), TOP_ONLY)
	local fillBlocks = math.min(h, theme.FillDepth or 3)
	local fillH = fillBlocks * B
	block(parent, theme.Fill, theme.Fill, Vector3.new(sizeU, fillH, B), at(u, top - fillH / 2, v), SIDES_ONLY)
	local deepH = (h - fillBlocks) * B
	if deepH > 0 then
		block(parent, theme.Deep, theme.Deep, Vector3.new(sizeU, deepH, B), at(u, baseY + deepH / 2, v), SIDES_ONLY)
	end
end

for j = minJ, maxJ do
	local i = minI
	while i <= maxI do
		local cell = hills[key(i, j)]
		if not cell then
			i += 1
		else
			local last = i
			while last + 1 <= maxI and last - i + 1 < MAX_RUN do
				local nextCell = hills[key(last + 1, j)]
				if not nextCell or nextCell.H ~= cell.H or nextCell.Theme ~= cell.Theme or nextCell.Y ~= cell.Y then
					break
				end
				last += 1
			end
			local len = last - i + 1
			column(folderOf(cell.Region.Name, "Hills"), cell.Theme, cell.Y, cell.H, (i + len / 2) * B, (j + 0.5) * B, len * B)
			i = last + 1
		end
	end
end

local function topOf(cell)
	return cell.Y + cell.H * B + CAP
end

---------------------------------------------------------------- ХОЛМЫ: ДЕРЕВЬЯ, ПРЕДМЕТЫ, ФОНАРИ
local blocked = {} -- клетки, где уже что-то стоит
local function blockAround(i, j, radius)
	for di = -radius, radius do
		for dj = -radius, radius do
			blocked[key(i + di, j + dj)] = true
		end
	end
end
-- Листва не должна нависать над спавном и биомами
local function farFromInterior(i, j, radius)
	for di = -radius, radius do
		for dj = -radius, radius do
			if interior[key(i + di, j + dj)] then
				return false
			end
		end
	end
	return true
end

local placedTrees = {}
local treeCount, lanternCount = 0, 0
for j = minJ, maxJ do
	for i = minI, maxI do
		local cell = hills[key(i, j)]
		local theme = cell and cell.Theme
		if cell and theme.TreeChance and theme.TreeChance > 0 and cell.R >= 3
			and not blocked[key(i, j)] and farFromInterior(i, j, 2) and rng:NextNumber() < theme.TreeChance then
			local gap = theme.TreeGap or 5
			local free = true
			for _, other in ipairs(placedTrees) do
				if math.max(math.abs(other[1] - i), math.abs(other[2] - j)) < gap then
					free = false
					break
				end
			end
			if free then
				table.insert(placedTrees, { i, j })
				tree(pickWeighted(theme.Trees), folderOf(cell.Region.Name, "Trees"), (i + 0.5) * B, (j + 0.5) * B, topOf(cell))
				treeCount += 1
				blockAround(i, j, 2)
			end
		end
	end
end

for j = minJ, maxJ do
	for i = minI, maxI do
		local k = key(i, j)
		local cell = hills[k]
		if cell and not blocked[k] then
			local theme = cell.Theme
			local u, v, y = (i + 0.5) * B, (j + 0.5) * B, topOf(cell)
			if theme.Lanterns and LANTERN_EVERY > 0 and cell.R == 1 and (i + j) % LANTERN_EVERY == 0 then
				-- Фонарь на краю холма спавна
				local parent = folderOf(cell.Region.Name, "Lanterns")
				box(parent, "Log", u, y, v, 1, 6, 1, SIDES_ONLY)
				glow(box(parent, "Lamp", u, y + 6, v, 2, 2, 2), 24, 1.2)
				lanternCount += 1
				blocked[k] = true
			else
				local prop = rollChances(theme.HillProps)
				if prop then
					PROPS[prop]({ Parent = folderOf(cell.Region.Name, "Props"), U = u, V = v, Y = y, Inward = cell.Inward, Theme = theme })
					blocked[k] = true
				else
					local plant = rollChances(theme.HillPlants)
					if plant then
						PLANTS[plant](folderOf(cell.Region.Name, "Plants"), u + rng:NextNumber(-1.2, 1.2), y, v + rng:NextNumber(-1.2, 1.2))
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- ЗЕМЛЯ СПАВНА И ТРОПИНКА
do
	local s = spawnRegion
	local lift = 0.05 -- чуть выше низа полов, чтобы не мерцать со старой землёй
	local u0, u1 = s.I0 * B, (s.I1 + 1) * B
	local v0, v1 = s.J0 * B, (s.J1 + 1) * B
	box(folderOf("Spawn", "Ground"), "GrassTop", (u0 + u1) / 2, s.Y + lift - 4, (v0 + v1) / 2, u1 - u0, 4, v1 - v0, TOP_ONLY)

	-- Тропинка от середины спавна к первому биому, неровная по краям
	local first = regions[1]
	if PATH_WIDTH > 0 then
		local pathU = first and (first.I0 + first.I1 + 1) / 2 * B or (u0 + u1) / 2
		pathU = math.clamp(pathU, u0 + PATH_WIDTH * B, u1 - PATH_WIDTH * B)
		local parent = folderOf("Spawn", "Path")
		for j = math.floor((s.J0 + s.J1) / 2), s.J1 do
			local width = PATH_WIDTH + rng:NextInteger(-1, 1)
			local shift = rng:NextInteger(-1, 1) * 0.5 * B
			decor(box(parent, "Path", pathU + shift, s.Y + lift, (j + 0.5) * B, width * B, 0.2, B, TOP_ONLY))
		end
	end

	-- SafeZone не трогаем. Если её нет — делаем невидимую на весь спавн.
	if not workspace:FindFirstChild("SafeZone") then
		local zone = Instance.new("Part")
		zone.Name = "SafeZone"
		zone.Anchored = true
		zone.CanCollide = false
		zone.CanQuery = false
		zone.CanTouch = false
		zone.Transparency = 1
		zone.Size = Vector3.new(u1 - u0, 60, v1 - v0)
		zone.CFrame = at((u0 + u1) / 2, s.Y + 30, (v0 + v1) / 2)
		zone.Parent = workspace
		print("[BlockWorld] SafeZone не было — сделал невидимую на весь спавн.")
	end
end

---------------------------------------------------------------- ВНУТРИ БИОМОВ
for _, region in ipairs(regions) do
	local theme = region.Theme
	local model = region.Model
	local floorTop = region.Y + (GROUND_OVERLAY and 0.2 or 0)

	-- Где ничего не ставить: точки яиц, ворота, босс
	local clear = {}
	local function clearRect(u0, u1, v0, v1, pad)
		local i0, j0 = cellOf(u0, v0)
		local i1, j1 = cellOf(u1, v1)
		for i = i0 - pad, i1 + pad do
			for j = j0 - pad, j1 + pad do
				clear[key(i, j)] = true
			end
		end
	end
	local spawns = model:FindFirstChild("EggSpawns", true)
	for _, d in ipairs(spawns and spawns:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			local u, v = toUV(d.Position)
			clearRect(u, u, v, v, KEEP_CLEAR)
		end
	end
	local gate = model:FindFirstChild("Gate", true)
	if gate then
		local u0, u1, v0, v1 = rectOf(gate)
		clearRect(u0, u1, v0, v1, 1)
	end
	local bossSpawn = model:FindFirstChild("BossSpawn", true)
	if bossSpawn then
		local u0, u1, v0, v1 = rectOf(bossSpawn)
		clearRect(u0, u1, v0, v1, KEEP_CLEAR)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Humanoid") and d.Parent and d.Parent:IsA("Model") then
			local u0, u1, v0, v1 = rectOf(d.Parent)
			clearRect(u0, u1, v0, v1, KEEP_CLEAR)
		end
	end

	-- Пол в стиле биома
	local u0, u1 = region.I0 * B, (region.I1 + 1) * B
	local v0, v1 = region.J0 * B, (region.J1 + 1) * B
	if GROUND_OVERLAY and theme.Ground then
		box(folderOf(region.Name, "Ground"), theme.Ground, (u0 + u1) / 2, region.Y, (v0 + v1) / 2, u1 - u0, 0.2, v1 - v0, TOP_ONLY)
	end

	-- Пятна: каждое — случайное «пятно» из клеток, склеенное по рядам
	local patchOf = {} -- [key] = вид пятна
	local cellsTotal = (region.I1 - region.I0 + 1) * (region.J1 - region.J0 + 1)
	if theme.Patches and theme.PatchDensity and theme.PatchDensity > 0 then
		local patchFolder = folderOf(region.Name, "Patches")
		local covered, target = 0, cellsTotal * theme.PatchDensity
		local attempts = 0
		while covered < target and attempts < 200 do
			attempts += 1
			local spec = PATCHES[pickWeighted(theme.Patches)]
			local size = rng:NextInteger(spec.Size[1], spec.Size[2])
			local start = { rng:NextInteger(region.I0, region.I1), rng:NextInteger(region.J0, region.J1) }
			if not patchOf[key(start[1], start[2])] then
				local cells = { start }
				local mine = { [key(start[1], start[2])] = true }
				local tries = 0
				while #cells < size and tries < size * 8 do
					tries += 1
					local from = cells[rng:NextInteger(1, #cells)]
					local dir = ({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } })[rng:NextInteger(1, 4)]
					local i, j = from[1] + dir[1], from[2] + dir[2]
					local k = key(i, j)
					if i >= region.I0 and i <= region.I1 and j >= region.J0 and j <= region.J1 and not mine[k] and not patchOf[k] then
						mine[k] = true
						table.insert(cells, { i, j })
					end
				end
				for _, c in ipairs(cells) do
					patchOf[key(c[1], c[2])] = spec
				end
				covered += #cells
				-- Склеиваем клетки пятна по рядам
				local lit = false
				for j = region.J0, region.J1 do
					local i = region.I0
					while i <= region.I1 do
						if mine[key(i, j)] then
							local last = i
							while last + 1 <= region.I1 and mine[key(last + 1, j)] do
								last += 1
							end
							local len = last - i + 1
							local part = decor(box(patchFolder, spec.Kind, (i + len / 2) * B, floorTop, (j + 0.5) * B, len * B, 0.1, B, TOP_ONLY))
							if spec.Glow and not lit then
								glow(part, 16, 1)
								lit = true
							end
							i = last + 1
						else
							i += 1
						end
					end
				end
			end
		end
	end

	-- Трава и цветы по полу (без столкновений); на пятнах — свои растения
	local plantFolder = folderOf(region.Name, "Plants")
	local propFolder = folderOf(region.Name, "Props")
	local edgeBand = theme.EdgeBand or EDGE_BAND
	local edgeBlocked = {}
	for j = region.J0, region.J1 do
		for i = region.I0, region.I1 do
			local k = key(i, j)
			if not clear[k] then
				local u, v = (i + 0.5) * B, (j + 0.5) * B
				local spec = patchOf[k]
				local nearEdge = (i - region.I0) < edgeBand or (region.I1 - i) < edgeBand
				local placedProp = false
				if nearEdge and not spec and not edgeBlocked[k] and theme.EdgeProps and theme.EdgeChance
					and rng:NextNumber() < theme.EdgeChance then
					local name = pickWeighted(theme.EdgeProps)
					PROPS[name]({ Parent = propFolder, U = u, V = v, Y = floorTop, Inward = i < (region.I0 + region.I1) / 2 and 1 or -1, Theme = theme })
					placedProp = true
					local radius = name == "Tree" and 2 or 1
					for di = -radius, radius do
						for dj = -radius, radius do
							edgeBlocked[key(i + di, j + dj)] = true
						end
					end
				end
				if not placedProp then
					local plant = rollChances(spec and spec.Plants or (not spec and theme.Plants) or nil)
					if plant then
						PLANTS[plant](plantFolder, u + rng:NextNumber(-1.2, 1.2), floorTop + (spec and 0.1 or 0), v + rng:NextNumber(-1.2, 1.2))
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- ОБЛАКА
if CLOUDS > 0 and minI <= maxI then
	local cloudsFolder = folderOf("Sky", "Clouds")
	local highest = groundY
	for _, region in ipairs(regions) do
		highest = math.max(highest, region.Y)
	end
	for _ = 1, CLOUDS do
		local u = rng:NextNumber(minI * B - 100, maxI * B + 100)
		local v = rng:NextNumber(minJ * B - 100, maxJ * B + 100)
		local y = highest + 18 * B + 60 + rng:NextNumber(-10, 10)
		local w, d = rng:NextInteger(6, 12) * B, rng:NextInteger(4, 8) * B
		local m = Instance.new("Model")
		m.Name = "Cloud"
		m.Parent = cloudsFolder
		for _, p in ipairs({
			block(m, "Cloud", "Cloud", Vector3.new(w, B, d), at(u, y, v)),
			block(m, "Cloud", "Cloud", Vector3.new(w * 0.6, B, d * 0.6),
				at(u + rng:NextNumber(-w, w) * 0.3, y + B, v + rng:NextNumber(-d, d) * 0.3)),
		}) do
			decor(p)
			p.Transparency = 0.1
		end
	end
end

---------------------------------------------------------------- НЕВИДИМАЯ СТЕНА
-- По двум внешним рядам холмов (толщина 8: на большой скорости тонкие стены пролетают).
-- Клетки склеиваются в большие прямоугольники, чтобы деталей было мало.
do
	local barrierFolder = folderOf("Sky", "Barrier")
	local isWall = {}
	for j = minJ, maxJ do
		for i = minI, maxI do
			local cell = hills[key(i, j)]
			if cell and cell.R >= cell.Rows - 1 then
				isWall[key(i, j)] = cell
			end
		end
	end
	local done = {}
	local function free(i, j)
		local k = key(i, j)
		return isWall[k] ~= nil and not done[k]
	end
	for j = minJ, maxJ do
		for i = minI, maxI do
			if free(i, j) then
				local w = 1
				while free(i + w, j) do
					w += 1
				end
				local h = 1
				while true do
					local ok = true
					for ii = i, i + w - 1 do
						if not free(ii, j + h) then
							ok = false
							break
						end
					end
					if not ok then
						break
					end
					h += 1
				end
				local yMin, yMax = math.huge, -math.huge
				for jj = j, j + h - 1 do
					for ii = i, i + w - 1 do
						local k = key(ii, jj)
						done[k] = true
						yMin, yMax = math.min(yMin, isWall[k].Y), math.max(yMax, isWall[k].Y)
					end
				end
				local height = yMax - yMin + BARRIER_HEIGHT
				local p = Instance.new("Part")
				p.Name = "Barrier"
				p.Anchored = true
				p.Size = Vector3.new(w * B, height, h * B)
				p.CFrame = at((i + w / 2) * B, yMin + height / 2, (j + h / 2) * B)
				p.Transparency = 1
				p.CanQuery = false -- камера сквозь неё не упирается
				p.CastShadow = false
				p.Parent = barrierFolder
				partCount += 1
			end
		end
	end
end

---------------------------------------------------------------- ГОТОВО
root.Parent = workspace
ChangeHistoryService:SetWaypoint("Build WorldDecor")

local names = {}
for _, region in ipairs(regions) do
	table.insert(names, region.Name)
end
print(string.format("[BlockWorld] Готово: участков %d, биомы по порядку: %s (в сторону %s).",
	plotCount, #names > 0 and table.concat(names, " -> ") or "нет", exitName))
print(string.format("[BlockWorld] Деревьев %d, фонарей %d, подсветок %d из %d, деталей всего %d.",
	treeCount, lanternCount, lightsUsed, MAX_LIGHTS, partCount))
if #missingThemes > 0 then
	warn("[BlockWorld] Нет стиля для биомов: " .. table.concat(missingThemes, ", ")
		.. " — взят стиль Plains. Имена стилей: Plains, Forest, Desert, Snow, Swamp, Nether, CrystalCave.")
end
local expected = { "Plains", "Forest", "Desert", "Snow", "Swamp", "Nether", "CrystalCave" }
local missingModels = {}
for _, name in ipairs(expected) do
	local found = false
	for _, region in ipairs(regions) do
		if string.gsub(region.Name, "%s", "") == name then
			found = true
		end
	end
	if not found then
		table.insert(missingModels, name)
	end
end
if #missingModels > 0 then
	print("[BlockWorld] Ещё нет моделей биомов в Workspace.Biomes: " .. table.concat(missingModels, ", "))
end
