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
--   Новые биомы — каких биомов из BIOME_ORDER нет, те создаются сами за последним
--            существующим, того же размера (Area, Floor, Gate, BossSpawn, EggSpawns).
--
-- Существующие участки, SafeZone, биомы, ворота, точки яиц и боссов скрипт НЕ двигает.
-- Возле точек яиц, ворот и босса предметы не ставятся (KEEP_CLEAR).
--
-- Что нужно в Workspace:
--   Plots                — участки (как для игры).
--   Biomes.<Имя>         — модель биома с деталью Area (объём биома). Имена стилей:
--                          Plains, Forest, Desert, Snow, Swamp, Underworld, CrystalCave.
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
local MAX_RUN = 8          -- сколько одинаковых блоков подряд склеивать в одну деталь
local MAX_STEP = 2         -- самая большая разница высот соседних столбиков холмов (в блоках)
local BARRIER_HEIGHT = 400 -- высота невидимой стены по внешнему краю (чтобы не улететь от толчка)
local MAX_LIGHTS = 60      -- сколько всего светящихся предметов с подсветкой (больше — тормозит)
local EXIT = "auto"        -- куда от спавна идут биомы: "auto", "+X", "-X", "+Z", "-Z"
local SEED = 7             -- поменяй число, чтобы холмы и предметы встали по-другому

-- Производительность
local USE_MATERIALS = true -- картинки блоков — материалом детали (MaterialVariant в MaterialService),
                           -- а не объектами Texture. Texture рисуется отдельно на каждой грани каждой
                           -- детали, тысячи таких — главный источник лагов. false — старый способ.
local PLANT_DENSITY = 0.6  -- множитель травы, цветов и прочей мелочи (1 — как было; меньше — меньше деталей)
local STREAMING_LOD = true -- холмы, деревья и постройки видны издалека упрощённой моделью, даже если
                           -- сами детали ещё не загрузились (работает при Workspace.StreamingEnabled)

-- Спавн
local SPAWN_MARGIN = 12    -- свободное место между участками (на максимуме) и холмами, студы
local SPAWN_ROWS = 8       -- глубина холмов спавна в блоках
local LANTERN_EVERY = 7    -- фонарь на краю холма через каждые N блоков (0 — без фонарей)
local PATH_WIDTH = 2       -- ширина тропинок от участков к площадке и к выходу, в блоках (0 — без них)
local PLAZA_RADIUS = 4     -- радиус площадки посреди спавна, где сходятся тропинки (в блоках)

-- Граница safe zone и первого биома: красная линия по краю Workspace.SafeZone и надпись на земле
local SAFE_LINE = true                   -- false — без линии и надписи
local SAFE_LINE_WIDTH = 1.5              -- ширина линии, студы
local SAFE_LINE_COLOR = Color3.fromRGB(230, 35, 35)
local SAFE_SIGN_IMAGE = 125040199987845  -- Id картинки "Safe Zone" (0 — без надписи)
local SAFE_SIGN_SIZE = Vector2.new(48, 24) -- место под картинку на земле: ширина вдоль линии и глубина, студы.
                                           -- Картинка вписывается в него без растяжения.
local SAFE_SIGN_GAP = 2                  -- отступ надписи от линии внутрь safe zone, студы
local SAFE_SIGN_FLIP = false             -- надпись вверх ногами для идущих из Plains — поставь true

-- Биомы
local BIOME_ROWS = 7       -- глубина холмов по бокам биома в блоках
local EDGE_BAND = 2        -- на сколько блоков от края биома внутрь можно ставить твёрдые предметы
local KEEP_CLEAR = 3       -- сколько блоков вокруг точек яиц, ворот и босса оставить пустыми
local GROUND_OVERLAY = true -- застелить пол биома землёй в его стиле
local CLOUDS = 30          -- сколько облаков над всей картой
local CREATE_BIOMES = true -- создать недостающие биомы из BIOME_ORDER за первым биомом
local BIOME_LENGTH_GROWTH = 1.25 -- каждый следующий биом во столько раз длиннее предыдущего
                                 -- (1 — все как первый). Чем длиннее биом, тем дольше бежать от босса.
local LANDMARKS = true     -- постройка на склоне у каждого биома (мельница, пирамида, крепость...)
local FEATURES = true      -- речки, озёра и прочее внутри биомов (без столкновений)
local BIOME_ORDER = { "Plains", "Forest", "Desert", "Snow", "Swamp", "Underworld", "CrystalCave" }

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
	DarkBrick = { Texture = "StoneBrick", Tint = rgb(120, 60, 64), Colors = { rgb(64, 26, 30) } },
	SandBrick = { Texture = "StoneBrick", Tint = rgb(240, 220, 160), Colors = { rgb(205, 186, 130) } },
	Planks = { Texture = "Log", Tint = rgb(235, 205, 160), Colors = { rgb(160, 120, 70) } },
	Canvas = { Colors = { rgb(235, 228, 210), rgb(225, 218, 200) } },
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
	Underworld = {
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
	-- Command Bar запоминает модуль после первого require и потом отдаёт старую копию,
	-- даже если файл поменялся. Копия модуля — всегда свежие числа.
	local fresh = node:Clone()
	local ok, result = pcall(require, fresh)
	fresh:Destroy()
	return ok and result or nil
end

-- Id текстуры в виде текста из одних цифр. Длинное число нельзя просто
-- превратить в текст: может получиться "1.13e+14", поэтому %d.
local function textureId(value)
	if type(value) == "number" then
		return value > 0 and string.format("%d", value) or nil
	end
	local digits = value and string.match(tostring(value), "%d+")
	return digits ~= "0" and digits or nil
end

local TEXTURES = {}
do
	local raw = tryRequire({ "Shared", "Config", "BlockTextures" })
	if not raw then
		warn("[BlockWorld] Не найден Config/BlockTextures — блоки будут без текстур. Rojo подключён?")
	else
		local count = 0
		for name, value in pairs(raw) do
			TEXTURES[name] = textureId(value)
			if TEXTURES[name] then
				count += 1
			end
		end
		print("[BlockWorld] Текстур с Id: " .. count)
	end
end

-- Материал на каждую картинку: MaterialVariant "Block<Имя>" в MaterialService.
-- Картинка ложится на все грани детали, цвет детали её подкрашивает (Tint).
local MaterialService = game:GetService("MaterialService")
local MATERIAL_BASE = Enum.Material.Plastic
local variantOf = {} -- [имя картинки] = имя MaterialVariant
if USE_MATERIALS then
	for name, id in pairs(TEXTURES) do
		local variantName = "Block" .. name
		local variant = MaterialService:FindFirstChild(variantName)
		if not (variant and variant:IsA("MaterialVariant")) then
			variant = Instance.new("MaterialVariant")
			variant.Name = variantName
		end
		variant.BaseMaterial = MATERIAL_BASE
		variant.ColorMap = "rbxassetid://" .. id
		variant.StudsPerTile = B -- одна плитка картинки = один блок
		variant.MaterialPattern = Enum.MaterialPattern.Regular
		variant.Parent = MaterialService
		variantOf[name] = variantName
	end
end

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
-- То же для травы и цветов, но реже в PLANT_DENSITY раз
local function rollPlant(chances)
	if PLANT_DENSITY < 1 and rng:NextNumber() >= PLANT_DENSITY then
		return nil
	end
	return rollChances(chances)
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
local plotFronts = {} -- середина входа каждого участка (откуда идёт тропинка)
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
		table.insert(plotFronts, frame:PointToWorldSpace(Vector3.new(0, 0, hz + B * 0.5)))
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
-- Большое и видное издалека — в модель с упрощённой копией для дальней дистанции
local LOD_GROUPS = { Hills = true, Trees = true, Landmark = true, Lanterns = true }
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
		local f
		if STREAMING_LOD and LOD_GROUPS[name] then
			f = Instance.new("Model")
			pcall(function()
				f.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
			end)
		else
			f = Instance.new("Folder")
		end
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

-- Есть ли у вида блока картинка
local function hasTexture(kind)
	local info = KINDS[kind]
	return info.Texture ~= nil and TEXTURES[info.Texture] ~= nil
end

-- Картинка вида kind на одну грань детали.
-- Одна плитка текстуры = один блок, поэтому склеенные блоки всё равно видны по отдельности.
local textureCount = 0
local function applyTexture(p, kind, face)
	if USE_MATERIALS then
		return -- картинка уже в материале детали
	end
	local info = KINDS[kind]
	local id = info.Texture and TEXTURES[info.Texture]
	if not id then
		return
	end
	local t = Instance.new("Texture")
	t.Texture = "rbxassetid://" .. id
	t.Face = face
	t.StudsPerTileU = B
	t.StudsPerTileV = B
	t.Color3 = info.Tint or Color3.new(1, 1, 1)
	t.Transparency = info.Transparency or 0
	t.Parent = p
	textureCount += 1
end

-- faces — на какие грани класть картинку (по умолчанию все, кроме низа).
-- Скрытым граням картинка не нужна: меньше объектов — меньше лагов.
local function block(parent, name, kind, size, cframe, faces)
	local info = KINDS[kind]
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = info.Colors[rng:NextInteger(1, #info.Colors)]
	p.Material = info.Material or Enum.Material.SmoothPlastic
	local variant = USE_MATERIALS and info.Texture and variantOf[info.Texture]
	if variant then
		-- Цвет детали умножается на картинку, как раньше Color3 у Texture
		p.Material = MATERIAL_BASE
		p.MaterialVariant = variant
		p.Color = info.Tint or Color3.new(1, 1, 1)
	end
	p.Transparency = info.Transparency or 0
	p.Reflectance = info.Reflectance or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for _, face in ipairs(faces or ALL_SIDES) do
		applyTexture(p, kind, face)
	end
	p.Parent = parent
	partCount += 1
	return p
end

-- Коробка: u, v — центр, y — низ, размеры в студах
local function box(parent, kind, u, y, v, su, sy, sv, faces)
	return block(parent, kind, kind, Vector3.new(su, sy, sv), at(u, y + sy / 2, v), faces)
end

-- Длинная плоская коробка (пол биома): у деталей Roblox предел 2048 студов,
-- поэтому длинное режется на куски вдоль v
local function longBox(parent, kind, u, y, v0, v1, su, sy, faces)
	local pieces = math.max(1, math.ceil((v1 - v0) / 2000))
	local step = (v1 - v0) / pieces
	local first
	for k = 0, pieces - 1 do
		local a = v0 + k * step
		local p = box(parent, kind, u, y, a + step / 2, su, sy, step, faces)
		first = first or p
	end
	return first
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

---------------------------------------------------------------- ВНУТРИ БИОМОВ: ОСОБЕННОСТИ
-- Всё плоское или без столкновений — бегать не мешает.
--   River  — речка поперёк биома (Width блоков), по краям берег Bank.
--   Pond   — озеро радиусом Radius блоков, по краю Rim.
--   Meadow — поляна: только растения Plants, без своей земли.
--   Ring   — круг из растений Plant радиусом Radius (грибной круг и т.п.).
-- Kind — из чего «вода» (может светиться: Glow). Plants/RimPlants/BankPlants — шанс на клетку.
local BIOME_FEATURES = {
	Plains = {
		{ Type = "River", Kind = "Water", Width = 3, Bank = "Sand", BankPlants = { Reed = 0.12, Flower = 0.1 } },
		{ Type = "Pond", Kind = "Water", Radius = { 3, 5 }, Rim = "Sand", Plants = { LilyPad = 0.2 }, RimPlants = { Reed = 0.25 } },
		{ Type = "Meadow", Radius = { 4, 6 }, Plants = { Flower = 0.35, Tuft = 0.25 }, Count = 2 },
	},
	Forest = {
		{ Type = "River", Kind = "Water", Width = 2, Bank = "CoarseDirt", BankPlants = { Fern = 0.3 } },
		{ Type = "Pond", Kind = "Water", Radius = { 2, 4 }, Rim = "Mud", Plants = { LilyPad = 0.25 }, RimPlants = { Fern = 0.3, Reed = 0.15 } },
		{ Type = "Ring", Plant = "SmallMushroom", Radius = 3, Count = 2 },
	},
	Desert = {
		{ Type = "Pond", Kind = "Water", Radius = { 4, 6 }, Rim = "GrassTop", Plants = { LilyPad = 0.1 }, RimPlants = { Reed = 0.35, Tuft = 0.25 } },
		{ Type = "River", Kind = "RedSand", Width = 3, Bank = "Sandstone", BankPlants = { DeadBush = 0.1 } },
	},
	Snow = {
		{ Type = "Pond", Kind = "Ice", Radius = { 6, 9 }, Rim = "Stone" },
		{ Type = "River", Kind = "Ice", Width = 3 },
	},
	Swamp = {
		{ Type = "River", Kind = "SwampWater", Width = 4, Bank = "Mud", Plants = { LilyPad = 0.12 }, BankPlants = { Reed = 0.3 } },
		{ Type = "Pond", Kind = "SwampWater", Radius = { 3, 5 }, Rim = "Mud", Plants = { LilyPad = 0.3 }, RimPlants = { Reed = 0.3 }, Count = 2 },
	},
	Underworld = {
		{ Type = "River", Kind = "Lava", Width = 3, Bank = "Ash", Glow = true, BankPlants = { Fire = 0.08 } },
		{ Type = "Pond", Kind = "Lava", Radius = { 3, 4 }, Rim = "Obsidian", Glow = true },
	},
	CrystalCave = {
		{ Type = "River", Kind = "CrystalCyan", Width = 2, Bank = "CrystalStone", Glow = true, BankPlants = { SmallCrystal = 0.2 } },
		{ Type = "Pond", Kind = "CrystalPurple", Radius = { 3, 4 }, Rim = "CrystalStone", Glow = true },
		{ Type = "Ring", Plant = "SmallCrystal", Radius = 3 },
	},
}

---------------------------------------------------------------- ПОСТРОЙКИ НА СКЛОНЕ
-- У каждого биома на одном склоне (по очереди слева и справа) вырезается ровная
-- площадка, на ней стоит постройка. Игроки туда не забираются (склон крутой),
-- поэтому бегать постройки не мешают, а из биома их хорошо видно.
-- c = { Parent, U, V (середина площадки), Y (её верх), Inward (+1/-1 — в сторону биома), Theme }
local BIOME_LANDMARKS = {
	Plains = "Windmill", Forest = "GreatTree", Desert = "Pyramid", Snow = "Igloo",
	Swamp = "WitchHut", Underworld = "Fortress", CrystalCave = "Geode",
}

-- Коробка в блоках от середины площадки: du > 0 — к биому, y — низ, su/sy/sv — размер
local function lb(c, kind, du, y, dv, su, sy, sv, faces)
	return box(c.Parent, kind, c.U + du * c.Inward * B, c.Y + y * B, c.V + dv * B, su * B, sy * B, sv * B, faces)
end
local function lbLeaves(c, kind, du, y, dv, su, sy, sv)
	local p = lb(c, kind, du, y, dv, su, sy, sv)
	p.CanCollide = false
	return p
end

local LANDMARK_BUILDERS = {}

-- Мельница: каменный низ, деревянная башня, крыша ступеньками и крылья крестом
LANDMARK_BUILDERS.Windmill = function(c)
	lb(c, "StoneBrick", 0, 0, 0, 3, 2, 3)
	lb(c, "Planks", 0, 2, 0, 3, 6, 3)
	lb(c, "Log", 0, 8, 0, 3.5, 0.5, 3.5)
	lb(c, "Log", 0, 8.5, 0, 2, 1, 2)
	lb(c, "Log", 0, 9.5, 0, 1, 1, 1)
	lb(c, "Coal", 1.52, 0, 0, 0.05, 1.5, 1)
	glow(lb(c, "Glow", 1.52, 4.5, 0, 0.05, 1, 1), 12, 0.8)
	local hubU = c.U + c.Inward * 1.75 * B
	local hubY = c.Y + 6.5 * B
	block(c.Parent, "Log", "Log", Vector3.new(0.6 * B, 0.6 * B, 0.6 * B), at(hubU, hubY, c.V))
	for k = 0, 3 do
		local cf = at(hubU + c.Inward * 0.4, hubY, c.V) * CFrame.Angles(math.rad(45 + k * 90), 0, 0)
		block(c.Parent, "Log", "Log", Vector3.new(0.3, 4.5 * B, 0.3), cf * CFrame.new(0, 2.25 * B, 0))
		block(c.Parent, "Canvas", "Canvas", Vector3.new(0.15, 3.5 * B, 1.2 * B), cf * CFrame.new(0, 2.6 * B, 0.65 * B))
	end
	lb(c, "Hay", -1, 0, 3.5, 1, 1, 1)
	lb(c, "Hay", 0, 0, 3.5, 1, 1, 1)
	lb(c, "Hay", -0.5, 1, 3.5, 1, 1, 1)
	lb(c, "Hay", 0.5, 0, -3.5, 1, 1, 1)
end

-- Огромное дерево: ствол 2x2, корни и широкая крона в четыре яруса
LANDMARK_BUILDERS.GreatTree = function(c)
	lb(c, "Log", 0, 0, 0, 2, 13, 2)
	for _, r in ipairs({ { 1.5, 0 }, { -1.5, 0 }, { 0, 1.5 }, { 0, -1.5 } }) do
		lb(c, "Log", r[1], 0, r[2], 1, 1.5, 1)
	end
	lbLeaves(c, "Leaves", 0, 10, 0, 9, 2, 7)
	lbLeaves(c, "Leaves", 0, 10, -4, 7, 2, 1)
	lbLeaves(c, "Leaves", 0, 10, 4, 7, 2, 1)
	lbLeaves(c, "Leaves", 0, 12, 0, 7, 2, 5)
	lbLeaves(c, "Leaves", 0, 12, -3, 5, 2, 1)
	lbLeaves(c, "Leaves", 0, 12, 3, 5, 2, 1)
	lbLeaves(c, "Leaves", 0, 14, 0, 5, 1, 3)
	lbLeaves(c, "Leaves", 0, 14, -2, 3, 1, 1)
	lbLeaves(c, "Leaves", 0, 14, 2, 3, 1, 1)
	lbLeaves(c, "Leaves", 0, 15, 0, 3, 1, 3)
	-- Светлячки под кроной
	for _ = 1, 5 do
		local p = decor(lb(c, "Glow", rng:NextNumber(-3, 3), rng:NextNumber(5, 9), rng:NextNumber(-4, 4), 0.12, 0.12, 0.12))
		glow(p, 8, 0.6)
	end
end

-- Пирамида ступеньками, вход со стороны биома и два обелиска
LANDMARK_BUILDERS.Pyramid = function(c)
	for k, s in ipairs({ 6, 4.5, 3, 1.5 }) do
		lb(c, "SandBrick", 0, (k - 1) * 1.5, 0, s, 1.5, s)
	end
	lb(c, "Coal", 3.02, 0, 0, 0.05, 1.5, 1)
	glow(lb(c, "Glow", 0, 6, 0, 0.6, 0.6, 0.6), 20, 1.2)
	for _, s in ipairs({ -1, 1 }) do
		lb(c, "Sandstone", 2.4, 0, s * 4.5, 1, 4, 1)
		lb(c, "SandBrick", 2.4, 4, s * 4.5, 0.6, 0.6, 0.6)
	end
end

-- Иглу с тоннелем ко входу, снеговик и ёлка
LANDMARK_BUILDERS.Igloo = function(c)
	lb(c, "Snow", -0.6, 0, 0, 5, 2, 3)
	lb(c, "Snow", -0.6, 0, -2, 3, 2, 1)
	lb(c, "Snow", -0.6, 0, 2, 3, 2, 1)
	lb(c, "Snow", -0.6, 2, 0, 3, 1, 3)
	lb(c, "Snow", -0.6, 3, 0, 1, 0.5, 1)
	lb(c, "Snow", 2.2, 0, 0, 1.2, 1.4, 1.6)
	lb(c, "Coal", 2.82, 0, 0, 0.05, 1, 0.8)
	PROPS.Snowman({ Parent = c.Parent, U = c.U + c.Inward * B, V = c.V + 4.5 * B, Y = c.Y, Inward = c.Inward, Theme = c.Theme })
	tree("SnowySpruce", c.Parent, c.U - c.Inward * B, c.V - 4.5 * B, c.Y)
end

-- Хижина на сваях с лесенкой, светящимся окном и котлом
LANDMARK_BUILDERS.WitchHut = function(c)
	for _, s in ipairs({ { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 } }) do
		lb(c, "Log", s[1], 0, s[2], 0.5, 3, 0.5)
	end
	lb(c, "Planks", 0, 3, 0, 4, 0.4, 4)
	lb(c, "SpruceLog", 0, 3.4, 0, 3.4, 2.6, 3.4)
	lb(c, "Planks", 0, 6, 0, 4.4, 0.5, 4.4)
	lb(c, "Planks", 0, 6.5, 0, 3, 0.5, 3)
	lb(c, "Planks", 0, 7, 0, 1.6, 0.5, 1.6)
	glow(lb(c, "Glow", 1.72, 4.3, 0.7, 0.05, 0.8, 0.8), 12, 0.8)
	lb(c, "Coal", 1.72, 3.4, -0.7, 0.05, 1.6, 0.8)
	for k = 1, 3 do
		lb(c, "Planks", 2 + k * 0.45, 3 - k * 0.8, -0.7, 0.45, 0.2, 0.8)
	end
	lb(c, "Coal", -0.5, 0, 3.6, 1, 0.8, 1)
	glow(decor(lb(c, "Lily", -0.5, 0.8, 3.6, 0.8, 0.05, 0.8)), 10, 0.8)
	for _ = 1, 6 do
		local du, dv = rng:NextNumber(-2, 2), (rng:NextNumber() < 0.5 and -2.05 or 2.05)
		decor(lb(c, "Vine", du, 3 - rng:NextNumber(0.5, 1.5), dv, 0.6, rng:NextNumber(0.5, 1.5), 0.08))
	end
end

-- Адская крепость: две башни с зубцами, стена с тёмным проёмом, лава перед воротами
LANDMARK_BUILDERS.Fortress = function(c)
	for _, s in ipairs({ -1, 1 }) do
		lb(c, "DarkBrick", 0, 0, s * 4.5, 3, 9, 3)
		for _, q in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			lb(c, "DarkBrick", q[1], 9, s * 4.5 + q[2], 1, 1, 1)
		end
		glow(lb(c, "Fire", 1.52, 6, s * 4.5, 0.05, 1.5, 1), 14, 1)
		PLANTS.Fire(c.Parent, c.U, c.Y + 9 * B, c.V + s * 4.5 * B)
	end
	lb(c, "DarkBrick", 0, 0, -2.25, 2, 6, 1.5)
	lb(c, "DarkBrick", 0, 0, 2.25, 2, 6, 1.5)
	lb(c, "DarkBrick", 0, 4, 0, 2, 2, 3)
	lb(c, "Coal", 0, 0, 0, 0.2, 4, 3)
	for k = -1, 1 do
		lb(c, "DarkBrick", 0, 6, k * 1.5, 1, 1, 0.8)
	end
	glow(decor(lb(c, "Lava", 2.2, 0, 0, 1.6, 0.15, 5)), 18, 1.2)
end

-- Жеода: веер огромных светящихся кристаллов и кристальный пруд
LANDMARK_BUILDERS.Geode = function(c)
	for k = 1, 9 do
		local kind = CRYSTALS[rng:NextInteger(1, #CRYSTALS)]
		local h = rng:NextNumber(3, 7) * B
		local w = rng:NextNumber(1.2, 2.2) * B
		local part = block(c.Parent, "Crystal", kind, Vector3.new(w, h, w),
			at(c.U + rng:NextNumber(-2, 1.5) * c.Inward * B, c.Y + h / 2 - B, c.V + rng:NextNumber(-5, 5) * B)
				* CFrame.Angles(math.rad(rng:NextNumber(-30, 30)), 0, math.rad(rng:NextNumber(-30, 30))))
		if k <= 3 then
			glow(part, 24, 1.5)
		end
	end
	decor(lb(c, "CrystalCyan", 2, 0, 0, 1.6, 0.15, 4))
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

-- Пол биома: сетка лучей сверху вниз, берём высоту, на которую попало больше всего лучей
-- (пол — самая частая поверхность, а предметы на нём у каждого луча свои).
-- Как в игре (WorldService), полом не считается то, сквозь что игрок проходит:
-- детали без столкновений и невидимые (зоны, хитбоксы).
local function findFloor(model, areaPart, areaCf, areaSize)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore = {}
	if areaPart then
		table.insert(ignore, areaPart)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "Area" or d.Name == "Gate" or d.Name == "EggSpawns" or d.Name == "BossSpawn" then
			table.insert(ignore, d)
		elseif d:IsA("Humanoid") and d.Parent then
			table.insert(ignore, d.Parent)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local top = areaCf.Position.Y + areaSize.Y / 2 + 50
	local down = Vector3.new(0, -(areaSize.Y + 400), 0)
	local function cast(origin)
		-- Невидимые детали со столкновениями (стены-хитбоксы) пропускаем и пускаем луч дальше
		for _ = 1, 20 do
			local result = workspace:Raycast(origin, down, params)
			if not result or result.Instance.Transparency < 0.95 then
				return result
			end
			params:AddToFilter(result.Instance)
		end
		return nil
	end
	local count = {} -- [высота] = сколько лучей в неё попало
	for a = -2, 2 do
		for b = -2, 2 do
			local p = areaCf:PointToWorldSpace(Vector3.new(a * 0.18 * areaSize.X, 0, b * 0.18 * areaSize.Z))
			local result = cast(Vector3.new(p.X, top, p.Z))
			if result then
				local y = math.floor(result.Position.Y * 10 + 0.5) / 10
				count[y] = (count[y] or 0) + 1
			end
		end
	end
	local best
	for y, n in pairs(count) do
		if not best or n > count[best] or (n == count[best] and y < best) then
			best = y
		end
	end
	return best or areaCf.Position.Y - areaSize.Y / 2
end

---------------------------------------------------------------- НОВЫЕ БИОМЫ
-- Биомы из BIOME_ORDER после первого (Plains) скрипт делает сам, друг за другом.
-- Ширина — как у первого, длина растёт: каждый следующий в BIOME_LENGTH_GROWTH раз
-- длиннее предыдущего (чем дальше биом, тем дольше бежать от босса).
-- В новом биоме: Area (невидимый объём), Floor (пол), Gate (копия ворот первого биома
-- у входа), BossSpawn (где спит босс — там же, где у первого) и EggSpawns (точки яиц).
--
-- Созданные скриптом биомы помечены атрибутом AutoBiome и при каждом запуске
-- перестраиваются под текущие настройки. То, что ты добавил в такой биом сам
-- (модель босса и т.п.), переносится в новый биом на то же место относительно входа.
-- Биом, который ты сделал сам (без метки), скрипт не трогает: следующие встанут за ним.
-- Чтобы скрипт больше не перестраивал биом — убери у модели атрибут AutoBiome.
local createdBiomes = {}
if CREATE_BIOMES then
	local OUR_PARTS = { Area = true, Floor = true, Gate = true, BossSpawn = true, EggSpawns = true }
	-- Биом этого скрипта: с меткой или (от прошлой версии) только из наших деталей
	local function isAuto(model)
		if model:GetAttribute("AutoBiome") then
			return true
		end
		for _, child in ipairs(model:GetChildren()) do
			if not OUR_PARTS[child.Name] then
				return false
			end
		end
		local floor = model:FindFirstChild("Floor")
		return floor ~= nil and floor:IsA("BasePart") and math.abs(floor.Size.Y - 4) < 0.01
			and model:FindFirstChild("BossSpawn") ~= nil
	end
	local function areaOf(model)
		local a = model:FindFirstChild("Area", true)
		return (a and a:IsA("BasePart")) and a or model
	end
	-- Сдвинуть детали и модели вместе со всем внутри (папки — по содержимому)
	local function shift(instance, offset)
		if instance:IsA("PVInstance") then
			instance:PivotTo(instance:GetPivot() + offset)
		else
			for _, child in ipairs(instance:GetChildren()) do
				shift(child, offset)
			end
		end
	end

	local byName = {}
	for _, m in ipairs(biomeModels) do
		byName[string.gsub(m.Name, "%s", "")] = m
	end
	local template = byName[BIOME_ORDER[1]]
	if not template or isAuto(template) then
		warn("[BlockWorld] Нет биома " .. BIOME_ORDER[1] .. " — по нему считается размер остальных. Новые биомы не созданы.")
	else
		if not biomesFolder then
			biomesFolder = Instance.new("Folder")
			biomesFolder.Name = "Biomes"
			biomesFolder.Parent = workspace
		end
		local tAreaPart = areaOf(template)
		tAreaPart = tAreaPart:IsA("BasePart") and tAreaPart or nil
		local tu0, tu1, tv0, tv1, tcf, tsize = rectOf(tAreaPart or template)
		local tFloor = findFloor(template, tAreaPart, tcf, tsize)
		local width = tu1 - tu0
		local areaH = tAreaPart and tAreaPart.Size.Y or 60
		local areaMidY = tAreaPart and (tAreaPart.Position.Y - tFloor) or areaH / 2
		local cu = (tu0 + tu1) / 2

		-- Где у первого биома спит босс (доля длины от входа) и на какой высоте точки яиц
		local bossU, bossT, bossY = cu, 0.75, 0
		local tBossSpawn = template:FindFirstChild("BossSpawn", true)
		local bossThing = (tBossSpawn and tBossSpawn:IsA("BasePart")) and tBossSpawn or nil
		if not bossThing then
			for _, d in ipairs(template:GetDescendants()) do
				if d:IsA("Humanoid") and d.Parent:IsA("Model") then
					bossThing = d.Parent
					break
				end
			end
		end
		if bossThing then
			local cf, size = boxOf(bossThing)
			local u, v = toUV(cf.Position)
			bossU, bossT = u, math.clamp((v - tv0) / (tv1 - tv0), 0.1, 0.95)
			bossY = bossThing:IsA("BasePart") and (cf.Position.Y - tFloor) or (cf.Position.Y - size.Y / 2 - tFloor)
		end
		local eggCount, eggY = 10, 1
		local tSpawns = template:FindFirstChild("EggSpawns", true)
		if tSpawns then
			local heights = {}
			for _, d in ipairs(tSpawns:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(heights, d.Position.Y - tFloor)
				end
			end
			if #heights > 0 then
				table.sort(heights)
				eggCount, eggY = #heights, heights[math.ceil(#heights / 2)]
			end
		end
		local tGate = template:FindFirstChild("Gate", true)

		local function marker(parent, name, size, cframe)
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.Size = size
			p.CFrame = cframe
			p.Transparency = 1
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Parent = parent
			return p
		end

		local startV = tv1
		local length = tv1 - tv0
		for index = 2, #BIOME_ORDER do
			local name = BIOME_ORDER[index]
			length *= BIOME_LENGTH_GROWTH
			local existing = byName[name]
			if existing and not isAuto(existing) then
				-- Биом автора: не трогаем, следующий встанет сразу за ним
				local _, _, ev0, ev1 = rectOf(areaOf(existing))
				startV, length = ev1, ev1 - ev0
			else
				local theme = THEMES[name] or THEMES.Plains
				local v0, v1 = startV, startV + length
				local cv = (v0 + v1) / 2
				local model = Instance.new("Model")
				model.Name = name
				model:SetAttribute("AutoBiome", true)
				model:SetAttribute("FloorY", tFloor) -- верх пола: его не надо искать лучами

				marker(model, "Area", Vector3.new(width, areaH, length), at(cu, tFloor + areaMidY, cv))

				-- Пол (кусками, если биом длиннее 2000 студов)
				local pieces = math.max(1, math.ceil(length / 2000))
				local firstFloor
				for k = 0, pieces - 1 do
					local floor = Instance.new("Part")
					floor.Name = "Floor"
					floor.Anchored = true
					floor.Size = Vector3.new(width, 4, length / pieces)
					floor.CFrame = at(cu, tFloor - 2, v0 + (k + 0.5) * length / pieces)
					floor.Color = KINDS[theme.Ground or "GrassTop"].Colors[1]
					floor.Material = Enum.Material.SmoothPlastic
					floor.TopSurface = Enum.SurfaceType.Smooth
					floor.Parent = model
					firstFloor = firstFloor or floor
				end
				model.PrimaryPart = firstFloor

				-- Ворота: копия ворот первого биома на том же месте относительно входа
				if tGate then
					local gate = tGate:Clone()
					gate.Name = "Gate"
					shift(gate, exitDir * (v0 - tv0))
					gate.Parent = model
				else
					marker(model, "Gate", Vector3.new(width, 40, 8), at(cu, tFloor + 20, v0 + 4))
				end

				-- Место сна босса (лицом ко входу)
				local bossV = v0 + bossT * length
				marker(model, "BossSpawn", Vector3.new(2, 1, 2), at(bossU, tFloor + bossY, bossV))

				-- Точки яиц: посередине по ширине, не у входа и не у босса.
				-- В длинном биоме точек больше, чтобы яйца были по всей длине.
				local spawnsFolder = Instance.new("Folder")
				spawnsFolder.Name = "EggSpawns"
				spawnsFolder.Parent = model
				local count = math.floor(eggCount * length / (tv1 - tv0) + 0.5)
				local placed = {}
				local bossPoint = Vector2.new(bossU, bossV)
				for _ = 1, count * 30 do
					if #placed >= count then
						break
					end
					local p = Vector2.new(rng:NextNumber(cu - width * 0.3, cu + width * 0.3), rng:NextNumber(v0 + length * 0.12, v1 - length * 0.08))
					local ok = (p - bossPoint).Magnitude > 20
					for _, other in ipairs(placed) do
						if (p - other).Magnitude < 16 then
							ok = false
							break
						end
					end
					if ok then
						table.insert(placed, p)
						marker(spawnsFolder, "EggSpawn", Vector3.new(1, 1, 1), at(p.X, tFloor + eggY, p.Y))
					end
				end

				-- Старый созданный биом: переносим то, что добавил автор, и удаляем
				if existing then
					local _, _, ov0 = rectOf(areaOf(existing))
					for _, child in ipairs(existing:GetChildren()) do
						if not OUR_PARTS[child.Name] then
							shift(child, exitDir * (v0 - ov0))
							child.Parent = model
						end
					end
					existing:Destroy()
					table.remove(biomeModels, table.find(biomeModels, existing))
				end

				model.Parent = biomesFolder
				table.insert(biomeModels, model)
				table.insert(createdBiomes, string.format("%s (%d студов)", name, math.floor(length + 0.5)))
				startV = v1
			end
		end
	end
end

local missingThemes = {}
for _, model in ipairs(biomeModels) do
	local themeName = string.gsub(model.Name, "%s", "")
	local theme = THEMES[themeName]
	if not theme or themeName == "Spawn" then
		table.insert(missingThemes, model.Name)
		theme = THEMES.Plains
		themeName = "Plains"
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
		ThemeName = themeName,
		I0 = roundCell(u0), I1 = roundCell(u1) - 1,
		J0 = roundCell(v0), J1 = roundCell(v1) - 1,
		Y = model:GetAttribute("AutoBiome") and model:GetAttribute("FloorY") or findFloor(model, areaPart, cf, size),
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

---------------------------------------------------------------- ХОЛМЫ: ВЫСОТА БЕЗ ОБРЫВОВ
-- Высота холма зависит от расстояния до ближайшей открытой площадки — спавна или
-- ЛЮБОГО биома, а не только своего. Иначе там, где холмы спавна встречаются с холмами
-- биома, низкий край одного стоит вплотную к высокому краю другого и выходит обрыв.
-- Потом соседние столбики выравниваются: разница не больше MAX_STEP блоков.
local NEIGHBORS = {}
for di = -1, 1 do
	for dj = -1, 1 do
		if di ~= 0 or dj ~= 0 then
			table.insert(NEIGHBORS, { di, dj })
		end
	end
end

local dist = {}
local queue, head = {}, 1
for _, region in ipairs({ spawnRegion, table.unpack(regions) }) do
	for i = region.I0, region.I1 do
		for j = region.J0, region.J1 do
			local k = key(i, j)
			if dist[k] == nil then
				dist[k] = 0
				table.insert(queue, { i, j })
			end
		end
	end
end
while head <= #queue do
	local c = queue[head]
	head += 1
	local d = dist[key(c[1], c[2])]
	for _, n in ipairs(NEIGHBORS) do
		local i, j = c[1] + n[1], c[2] + n[2]
		local k = key(i, j)
		if hills[k] and dist[k] == nil then
			dist[k] = d + 1
			table.insert(queue, { i, j })
		end
	end
end

for j = minJ, maxJ do
	for i = minI, maxI do
		local k = key(i, j)
		local cell = hills[k]
		if cell then
			local theme = cell.Theme
			cell.R = math.clamp(dist[k] or cell.Rows, 1, cell.Rows)
			local t = cell.Rows > 1 and (cell.R - 1) / (cell.Rows - 1) or 1
			local h = theme.MinHeight + t * (theme.MaxHeight - theme.MinHeight)
				+ math.noise(i * 0.17, j * 0.17, SEED + 0.5) * (theme.Bumps or 2) * 2
			cell.H = math.max(theme.MinHeight, math.floor(h + 0.5))
		end
	end
end

-- Площадка под постройку: на склоне биома (по очереди слева и справа), со 2-го ряда
-- холмов до последнего, 12 блоков в длину. Высота — на блок выше нижнего ряда, а
-- ближний ряд игрок не перепрыгнет, поэтому на площадку он не залезет.
if LANDMARKS then
	for index, region in ipairs(regions) do
		local name = BIOME_LANDMARKS[region.ThemeName]
		if name then
			local side = index % 2 == 1 and -1 or 1
			local midJ = math.floor((region.J0 + region.J1) / 2)
			local pj0, pj1 = math.max(region.J0, midJ - 6), math.min(region.J1, midJ + 5)
			local pi0, pi1
			if side < 0 then
				pi0, pi1 = region.I0 - region.Rows, region.I0 - 2
			else
				pi0, pi1 = region.I1 + 2, region.I1 + region.Rows
			end
			local ok = true
			for i = pi0, pi1 do
				for j = pj0, pj1 do
					local cell = hills[key(i, j)]
					if not cell or cell.Region ~= region then
						ok = false
					end
				end
			end
			if ok then
				local h = region.Theme.MinHeight + 1
				for i = pi0, pi1 do
					for j = pj0, pj1 do
						local cell = hills[key(i, j)]
						cell.H = h
						cell.Plateau = true
					end
				end
				region.Plateau = { I0 = pi0, I1 = pi1, J0 = pj0, J1 = pj1, Inward = -side, Name = name }
			end
		end
	end
end

for _ = 1, 40 do
	local changed = false
	for j = minJ, maxJ do
		for i = minI, maxI do
			local cell = hills[key(i, j)]
			if cell then
				for _, n in ipairs(NEIGHBORS) do
					local other = hills[key(i + n[1], j + n[2])]
					if other then
						local limit = other.Y + (other.H + MAX_STEP) * B
						if cell.Y + cell.H * B > limit + 0.01 then
							cell.H = math.max(1, math.floor((limit - cell.Y) / B + 0.01))
							changed = true
						end
					end
				end
			end
		end
	end
	if not changed then
		break
	end
end

---------------------------------------------------------------- ХОЛМЫ: СТРОИМ
-- Строится только то, что видит игрок («оболочка»): столбик идёт вниз не до земли,
-- а до верха самого низкого соседа — ниже его всё равно закрывают соседи.
-- Сзади холмов (за краем карты) — только верхний блок. Картинки — только на видимых
-- гранях, а трава сверху — картинкой на верхней грани, без отдельной детали.
-- Отдельный тонкий слой сверху ставится, только если у верхнего блока нет картинки
-- (с USE_MATERIALS — если верх из другого блока, чем слой под ним).
local function hasCap(theme)
	if USE_MATERIALS then
		-- Материал один на всю деталь: другой верх (трава на земле) — тонкой деталью сверху
		return theme.Top ~= theme.Fill
	end
	return not hasTexture(theme.Top)
end

local function topOf(cell)
	return cell.Y + cell.H * B + (hasCap(cell.Theme) and CAP or 0)
end

-- Верх соседней клетки и видна ли с той стороны грань (за краем карты — не видна)
local function neighborTop(i, j)
	local k = key(i, j)
	local n = hills[k]
	if n then
		return n.Y + n.H * B, true
	end
	local inside = interior[k]
	if inside then
		return inside.Y, true
	end
	return nil, false
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
			local theme = cell.Theme
			local top = cell.Y + cell.H * B
			local bottom = top - B -- хотя бы один блок
			local visible = {}
			local function look(ni, nj, face)
				local nTop, seen = neighborTop(ni, nj)
				if seen and nTop < top - 0.01 then
					bottom = math.min(bottom, nTop)
					visible[face] = true
				end
			end
			look(i - 1, j, Enum.NormalId.Left)
			look(last + 1, j, Enum.NormalId.Right)
			for ii = i, last do
				look(ii, j - 1, Enum.NormalId.Front)
				look(ii, j + 1, Enum.NormalId.Back)
			end
			-- Низ — по сетке блоков, чтобы картинки ложились ровно
			bottom = cell.Y + math.max(0, math.floor((bottom - cell.Y) / B + 0.01)) * B
			local faces = {}
			for _, face in ipairs(SIDES_ONLY) do
				if visible[face] then
					table.insert(faces, face)
				end
			end

			local len = last - i + 1
			local u, v, sizeU = (i + len / 2) * B, (j + 0.5) * B, len * B
			local parent = folderOf(cell.Region.Name, "Hills")
			local fillBottom = math.max(bottom, top - (theme.FillDepth or 3) * B)
			local fill = block(parent, theme.Fill, theme.Fill, Vector3.new(sizeU, top - fillBottom, B),
				at(u, (top + fillBottom) / 2, v), faces)
			if hasCap(theme) then
				block(parent, theme.Top, theme.Top, Vector3.new(sizeU, CAP, B), at(u, top + CAP / 2, v), TOP_ONLY)
			elseif not USE_MATERIALS then
				applyTexture(fill, theme.Top, Enum.NormalId.Top)
				fill.Color = KINDS[theme.Top].Colors[1]
			end
			if bottom < fillBottom - 0.01 then
				block(parent, theme.Deep, theme.Deep, Vector3.new(sizeU, fillBottom - bottom, B),
					at(u, (fillBottom + bottom) / 2, v), faces)
			end
			i = last + 1
		end
	end
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

-- Площадки под постройки (и по 2 блока вокруг) — без деревьев и мелочи
for _, region in ipairs(regions) do
	local p = region.Plateau
	if p then
		for i = p.I0 - 2, p.I1 + 2 do
			for j = p.J0 - 2, p.J1 + 2 do
				blocked[key(i, j)] = true
			end
		end
	end
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
					local plant = rollPlant(theme.HillPlants)
					if plant then
						PLANTS[plant](folderOf(cell.Region.Name, "Plants"), u + rng:NextNumber(-1.2, 1.2), y, v + rng:NextNumber(-1.2, 1.2))
					end
				end
			end
		end
	end
end

-- Постройки на площадках
local landmarkCount = 0
for _, region in ipairs(regions) do
	local p = region.Plateau
	local cell = p and hills[key(p.I0, p.J0)]
	if cell then
		LANDMARK_BUILDERS[p.Name]({
			Parent = folderOf(region.Name, "Landmark"),
			U = (p.I0 + p.I1 + 1) / 2 * B,
			V = (p.J0 + p.J1 + 1) / 2 * B,
			Y = topOf(cell),
			Inward = p.Inward,
			Theme = region.Theme,
		})
		landmarkCount += 1
	end
end

---------------------------------------------------------------- ЗЕМЛЯ СПАВНА И ТРОПИНКА
do
	local s = spawnRegion
	local lift = 0.05 -- чуть выше низа полов, чтобы не мерцать со старой землёй
	local u0, u1 = s.I0 * B, (s.I1 + 1) * B
	local v0, v1 = s.J0 * B, (s.J1 + 1) * B
	box(folderOf("Spawn", "Ground"), "GrassTop", (u0 + u1) / 2, s.Y + lift - 4, (v0 + v1) / 2, u1 - u0, 4, v1 - v0, TOP_ONLY)

	-- Тропинки: от входа каждого участка к круглой площадке посреди спавна,
	-- и от площадки к проходу в первый биом. Плоские, бегать не мешают.
	local first = regions[1]
	if PATH_WIDTH > 0 then
		local pathCells = {}
		local lo = -math.floor(PATH_WIDTH / 2)
		local function stamp(u, v)
			local ci, cj = cellOf(u, v)
			for di = lo, lo + PATH_WIDTH - 1 do
				for dj = lo, lo + PATH_WIDTH - 1 do
					local i, j = ci + di, cj + dj
					if i >= s.I0 and i <= s.I1 and j >= s.J0 and j <= s.J1 then
						pathCells[key(i, j)] = true
					end
				end
			end
		end
		local function line(au, av, bu, bv)
			local steps = math.max(1, math.ceil(math.sqrt((bu - au) ^ 2 + (bv - av) ^ 2) / (B * 0.5)))
			for t = 0, steps do
				local a = t / steps
				stamp(au + (bu - au) * a, av + (bv - av) * a)
			end
		end
		local cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
		local exitU = first and (first.I0 + first.I1 + 1) / 2 * B or cu
		for _, front in ipairs(plotFronts) do
			local fu, fv = toUV(front)
			line(fu, fv, cu, cv)
		end
		line(cu, cv, exitU, v1)
		-- Площадка: круг с неровным краем
		local ci, cj = cellOf(cu, cv)
		for di = -PLAZA_RADIUS - 1, PLAZA_RADIUS + 1 do
			for dj = -PLAZA_RADIUS - 1, PLAZA_RADIUS + 1 do
				if math.sqrt(di * di + dj * dj) <= PLAZA_RADIUS + math.noise(di * 0.5, dj * 0.5, SEED) then
					pathCells[key(ci + di, cj + dj)] = true
				end
			end
		end
		local parent = folderOf("Spawn", "Path")
		for j = s.J0, s.J1 do
			local i = s.I0
			while i <= s.I1 do
				if pathCells[key(i, j)] then
					local last = i
					while last + 1 <= s.I1 and pathCells[key(last + 1, j)] do
						last += 1
					end
					local len = last - i + 1
					decor(box(parent, "Path", (i + len / 2) * B, s.Y + lift, (j + 0.5) * B, len * B, 0.2, B, TOP_ONLY))
					i = last + 1
				else
					i += 1
				end
			end
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

---------------------------------------------------------------- ГРАНИЦА SAFE ZONE
-- Красная линия по краю SafeZone со стороны первого биома (там, где игра и правда
-- перестаёт считать игрока в безопасности) и картинка "Safe Zone" на земле перед ней.
-- Линия идёт по ширине первого биома: по бокам всё равно холмы.
if SAFE_LINE and regions[1] then
	local first = regions[1]
	local zone = workspace:FindFirstChild("SafeZone")
	local zoneParts = {}
	if zone and zone:IsA("BasePart") then
		table.insert(zoneParts, zone)
	elseif zone then
		for _, d in ipairs(zone:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Area" then
				table.insert(zoneParts, d)
			end
		end
		if #zoneParts == 0 then
			table.insert(zoneParts, zone) -- модель без деталей Area: по габариту всей модели
		end
	end

	-- Край зоны, ближайший к биому: из деталей, что напротив входа в биом, — самый дальний от спавна
	local pu0, pu1 = first.I0 * B, (first.I1 + 1) * B
	local borderV, lu0, lu1, facing
	for _, part in ipairs(zoneParts) do
		local u0, u1, _, v1 = rectOf(part)
		local overlaps = u1 > pu0 and u0 < pu1
		if not borderV or (overlaps and not facing) or (overlaps == facing and v1 > borderV) then
			borderV, facing = v1, overlaps
			lu0, lu1 = overlaps and math.max(u0, pu0) or u0, overlaps and math.min(u1, pu1) or u1
		end
	end

	if borderV and lu1 - lu0 >= 1 then
		-- Высота пола у линии: лучом вниз, мимо ворот, зон и всего, сквозь что проходят
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		local ignore = {}
		for _, d in ipairs(biomesFolder and biomesFolder:GetDescendants() or {}) do
			if d.Name == "Gate" or d.Name == "Area" then
				table.insert(ignore, d)
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
		local function floorAt(u)
			local origin = at(u, first.Y + 200, borderV).Position
			for _ = 1, 20 do
				local result = workspace:Raycast(origin, Vector3.new(0, -400, 0), params)
				if not result then
					return first.Y
				end
				if result.Instance.Transparency < 0.95 then
					return result.Position.Y
				end
				params:AddToFilter(result.Instance)
			end
			return first.Y
		end
		local cu = (lu0 + lu1) / 2
		local samples = { floorAt(lu0 + 2), floorAt(cu), floorAt(lu1 - 2) }
		table.sort(samples)
		-- Чуть выше земли биома и тропинок декора (они до +0.3 над полом), чтобы не мерцать
		local y = samples[2] + 0.3
		local parent = folderOf("Spawn", "SafeBorder")

		local line = Instance.new("Part")
		line.Name = "SafeZoneLine"
		line.Anchored = true
		line.Size = Vector3.new(lu1 - lu0, 0.1, SAFE_LINE_WIDTH)
		line.CFrame = at(cu, y + 0.05, borderV)
		line.Color = SAFE_LINE_COLOR
		line.Material = Enum.Material.Neon
		decor(line).Parent = parent
		partCount += 1

		local imageId = textureId(SAFE_SIGN_IMAGE)
		if imageId then
			local w = math.min(SAFE_SIGN_SIZE.X, lu1 - lu0)
			local d = SAFE_SIGN_SIZE.Y
			local sign = Instance.new("Part")
			sign.Name = "SafeZoneSign"
			sign.Anchored = true
			sign.Transparency = 1
			sign.Size = Vector3.new(w, 0.05, d)
			sign.CFrame = at(cu, y + 0.025, borderV - SAFE_LINE_WIDTH / 2 - SAFE_SIGN_GAP - d / 2)
				* CFrame.Angles(0, SAFE_SIGN_FLIP and math.pi or 0, 0)
			decor(sign).Parent = parent
			partCount += 1

			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 20
			gui.LightInfluence = 1 -- как краска на земле: ночью темнеет вместе с миром
			gui.Parent = sign
			local image = Instance.new("ImageLabel")
			image.Size = UDim2.fromScale(1, 1)
			image.BackgroundTransparency = 1
			image.Image = "rbxassetid://" .. imageId
			image.ScaleType = Enum.ScaleType.Fit
			image.Parent = gui
		end
		print(string.format("[BlockWorld] Граница safe zone: линия %d студов у входа в %s.", math.floor(lu1 - lu0 + 0.5), first.Name))
	else
		warn("[BlockWorld] Не нашёл край Workspace.SafeZone напротив " .. first.Name .. " — линию границы не к чему привязать.")
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
		longBox(folderOf(region.Name, "Ground"), theme.Ground, (u0 + u1) / 2, region.Y, v0, v1, u1 - u0, 0.2, TOP_ONLY)
	end

	local patchOf = {} -- [key] = что лежит на клетке пола (особенность или пятно)

	-- Особенности биома: речки, озёра, поляны, круги из растений (всё без столкновений)
	if FEATURES and BIOME_FEATURES[region.ThemeName] then
		local plantsHere = folderOf(region.Name, "Plants")
		local featureFolder = folderOf(region.Name, "Features")
		local function inside(i, j)
			return i >= region.I0 and i <= region.I1 and j >= region.J0 and j <= region.J1
		end
		local function mark(i, j, spec)
			local k = key(i, j)
			if inside(i, j) and not patchOf[k] then
				patchOf[k] = spec
				return true
			end
			return false
		end
		-- Круглое пятно с неровным краем
		local function blob(ci, cj, r)
			local cells = {}
			for di = -r - 1, r + 1 do
				for dj = -r - 1, r + 1 do
					if math.sqrt(di * di + dj * dj) <= r + math.noise(di * 0.35, dj * 0.35, ci * 0.1 + SEED) * 1.5 then
						table.insert(cells, { ci + di, cj + dj })
					end
				end
			end
			return cells
		end
		local spanI, spanJ = region.I1 - region.I0, region.J1 - region.J0
		for _, f in ipairs(BIOME_FEATURES[region.ThemeName]) do
			for _ = 1, f.Count or 1 do
				local main = { Kind = f.Kind, Plants = f.Plants, Glow = f.Glow }
				local edge = f.Rim or f.Bank
				local rim = edge and { Kind = edge, Plants = f.RimPlants or f.BankPlants } or nil
				local cells = {}
				if f.Type == "River" then
					-- Речка поперёк биома, извилистая
					local baseJ = region.J0 + rng:NextInteger(math.floor(spanJ * 0.3), math.floor(spanJ * 0.8))
					local amp, freq, phase = rng:NextNumber(2, 4), rng:NextNumber(0.08, 0.18), rng:NextNumber(0, 6.28)
					local w = f.Width or 3
					for i = region.I0, region.I1 do
						local c = baseJ + math.floor(amp * math.sin(i * freq + phase) + 0.5)
						for j = c - math.floor((w - 1) / 2), c + math.ceil((w - 1) / 2) do
							table.insert(cells, { i, j })
						end
					end
				elseif f.Type == "Pond" or f.Type == "Meadow" then
					local r = rng:NextInteger(f.Radius[1], f.Radius[2])
					if spanI > 2 * r + 4 and spanJ > 2 * r + 6 then
						local ci = rng:NextInteger(region.I0 + r + 2, region.I1 - r - 2)
						local cj = rng:NextInteger(region.J0 + r + 3, region.J1 - r - 3)
						cells = blob(ci, cj, r)
					end
				elseif f.Type == "Ring" then
					-- Круг из растений, без своей земли
					local r = f.Radius or 3
					if spanI > 2 * r + 4 and spanJ > 2 * r + 6 then
						local cu = (rng:NextInteger(region.I0 + r + 2, region.I1 - r - 2) + 0.5) * B
						local cv = (rng:NextInteger(region.J0 + r + 3, region.J1 - r - 3) + 0.5) * B
						local n = math.floor(r * 4)
						for k = 1, n do
							local a = k / n * math.pi * 2
							PLANTS[f.Plant](plantsHere, cu + math.cos(a) * r * B, floorTop, cv + math.sin(a) * r * B)
						end
					end
				end
				local mine = {}
				for _, c in ipairs(cells) do
					if mark(c[1], c[2], main) then
						mine[key(c[1], c[2])] = true
					end
				end
				if rim then
					for _, c in ipairs(cells) do
						if mine[key(c[1], c[2])] then
							for _, n in ipairs(NEIGHBORS) do
								mark(c[1] + n[1], c[2] + n[2], rim)
							end
						end
					end
				end
			end
		end
		-- Земля особенностей: клетки одного вида склеиваются по рядам
		local runs = 0
		for j = region.J0, region.J1 do
			local i = region.I0
			while i <= region.I1 do
				local spec = patchOf[key(i, j)]
				if spec and spec.Kind then
					local last = i
					while last + 1 <= region.I1 do
						local nextSpec = patchOf[key(last + 1, j)]
						if not nextSpec or nextSpec.Kind ~= spec.Kind then
							break
						end
						last += 1
					end
					local len = last - i + 1
					local part = decor(box(featureFolder, spec.Kind, (i + len / 2) * B, floorTop, (j + 0.5) * B, len * B, 0.1, B, TOP_ONLY))
					runs += 1
					if spec.Glow and runs % 6 == 0 then
						glow(part, 16, 1)
					end
					i = last + 1
				else
					i += 1
				end
			end
		end
	end

	-- Пятна: каждое — случайное «пятно» из клеток, склеенное по рядам
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
					local plant = rollPlant(spec and spec.Plants or (not spec and theme.Plants) or nil)
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
-- По двум внешним рядам холмов — тем, за которыми пустота (толщина 8: на большой
-- скорости тонкие стены пролетают). Клетки склеиваются в большие прямоугольники.
do
	local barrierFolder = folderOf("Sky", "Barrier")
	local isWall = {}
	local function isOutside(i, j)
		local k = key(i, j)
		return not hills[k] and not interior[k]
	end
	for j = minJ, maxJ do
		for i = minI, maxI do
			local cell = hills[key(i, j)]
			if cell then
				local nearOutside = false
				for di = -2, 2 do
					for dj = -2, 2 do
						if isOutside(i + di, j + dj) then
							nearOutside = true
						end
					end
				end
				if nearOutside then
					isWall[key(i, j)] = cell
				end
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
				while w < 500 and free(i + w, j) do
					w += 1
				end
				local h = 1
				while h < 500 do
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

-- Высота пола каждого биома: если какой-то сильно выше или ниже — он висит в воздухе
-- или утоплен, значит лучи нашли не тот пол (или модель биома стоит на другой высоте)
local heights = { string.format("низ участков %.1f", groundY) }
local uneven = {}
for _, region in ipairs(regions) do
	table.insert(heights, string.format("%s %.1f", region.Name, region.Y))
	if math.abs(region.Y - regions[1].Y) > 1 then
		table.insert(uneven, region.Name)
	end
end
print("[BlockWorld] Высота пола: " .. table.concat(heights, ", "))
if #uneven > 0 then
	warn("[BlockWorld] Пол не на уровне " .. regions[1].Name .. " у: " .. table.concat(uneven, ", ")
		.. ". Если это не задумано — проверь, что внутри Area этих биомов нет лишних деталей над полом"
		.. " и что сама модель биома стоит на той же высоте.")
end
if #createdBiomes > 0 then
	print("[BlockWorld] Биомы, построенные скриптом: " .. table.concat(createdBiomes, ", ")
		.. ". Если своей модели босса в биоме нет — игра ставит временного из кубиков.")
end
print(string.format("[BlockWorld] Деревьев %d, фонарей %d, построек %d, подсветок %d из %d, деталей всего %d, картинок Texture %d.",
	treeCount, lanternCount, landmarkCount, lightsUsed, MAX_LIGHTS, partCount, textureCount))

-- Настройки места, от которых сильно зависит скорость
local okTech, technology = pcall(function()
	return game:GetService("Lighting").Technology
end)
if okTech and technology == Enum.Technology.Future then
	warn("[BlockWorld] Lighting.Technology = Future — самое тяжёлое освещение. Для такой карты лучше ShadowMap.")
end
if STREAMING_LOD and not workspace.StreamingEnabled then
	print("[BlockWorld] Workspace.StreamingEnabled выключен — дальние упрощённые модели (STREAMING_LOD) не работают.")
end
if #missingThemes > 0 then
	warn("[BlockWorld] Нет стиля для биомов: " .. table.concat(missingThemes, ", ")
		.. " — взят стиль Plains. Имена стилей: Plains, Forest, Desert, Snow, Swamp, Underworld, CrystalCave.")
end
local expected = { "Plains", "Forest", "Desert", "Snow", "Swamp", "Underworld", "CrystalCave" }
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
