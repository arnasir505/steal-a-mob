-- WorldService: карта. Находит safe zone, биомы, ворота и точки спавна яиц,
-- и отвечает на вопросы "где игрок" и "открыт ли проход".
--
-- Что игра ждёт от карты:
--
--   Workspace
--    ├── SafeZone              деталь ИЛИ модель. Если модель — внутри детали
--    │                         с именем "Area" (их может быть несколько).
--    │                         Внутри safe zone яйцо считается добытым.
--    └── Biomes (папка)
--         └── Plains           имя модели = Id биома из Config/Biomes
--              ├── Area        деталь-объём биома. Если её нет, берётся
--              │               габарит всей модели (менее точно).
--              ├── Gate        необязательно. Ворота: закрываются на время сброса
--              │               раунда. Деталь или модель.
--              └── EggSpawns   необязательно. Папка с деталями-точками, где
--                              появляются яйца. Если её нет, точки выбираются
--                              случайно внутри Area, с поиском пола лучом.
--
-- Детали Area и границы можно делать невидимыми (Transparency = 1) и
-- без столкновений — игра смотрит только на их положение и размер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Biomes = require(ReplicatedStorage.Shared.Config.Biomes)

local WorldService = {}

local safeZoneBoxes = {}  -- список { CFrame, Size }
local ignoreParts = {}    -- служебные детали (зоны, ворота): пол под ними не ищем
local biomes = {}         -- [biomeId] = { Id, Config, Model, Boxes, Gate, Spawns }
local biomeOrder = {}     -- по порядку из Config/Biomes

---------------------------------------------------------------------
-- Объёмы
---------------------------------------------------------------------

local function boxFromPart(part)
	return { CFrame = part.CFrame, Size = part.Size }
end

-- Собирает объёмы из детали или модели.
-- У модели ищем детали с именем areaName; если их нет — берём общий габарит.
-- Сплошная Area мешает: игрок в неё не войдёт, а встанет сверху
local function warnIfSolid(part, label)
	if part.CanCollide then
		warn("[WorldService] " .. label .. ": деталь " .. part:GetFullName()
			.. " со столкновениями. Сделай Area невидимой и CanCollide = false,"
			.. " иначе она работает как стена.")
	end
end

local function collectBoxes(instance, areaName)
	local boxes = {}
	if not instance then
		return boxes
	end
	if instance:IsA("BasePart") then
		warnIfSolid(instance, "Зона")
		table.insert(ignoreParts, instance)
		table.insert(boxes, boxFromPart(instance))
		return boxes
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == areaName then
			warnIfSolid(descendant, "Зона")
			table.insert(ignoreParts, descendant)
			table.insert(boxes, boxFromPart(descendant))
		end
	end
	if #boxes == 0 and instance:IsA("Model") then
		local cframe, size = instance:GetBoundingBox()
		table.insert(boxes, { CFrame = cframe, Size = size })
	end
	return boxes
end

local function isInsideBox(box, position)
	local offset = box.CFrame:PointToObjectSpace(position)
	if math.abs(offset.X) > box.Size.X / 2 or math.abs(offset.Z) > box.Size.Z / 2 then
		return false
	end
	-- По высоте прощаем. Центр персонажа примерно на 3 студа выше пола,
	-- а если Area сделана сплошной коробкой, игрок стоит прямо на её крышке.
	local half = box.Size.Y / 2
	return offset.Y >= -half - GameConfig.Zone.HeightBelow
		and offset.Y <= half + GameConfig.Zone.HeightAbove
end

local function isInsideAny(boxes, position)
	for _, box in ipairs(boxes) do
		if isInsideBox(box, position) then
			return true
		end
	end
	return false
end

-- Разбор для тестовой команды !where: почему точка внутри или снаружи
function WorldService.DebugReport(position)
	local lines = {
		string.format("точка: %.0f / %.0f / %.0f", position.X, position.Y, position.Z),
	}
	local function report(name, boxes)
		if #boxes == 0 then
			table.insert(lines, name .. ": зона не найдена")
			return
		end
		for index, box in ipairs(boxes) do
			local offset = box.CFrame:PointToObjectSpace(position)
			table.insert(lines, string.format(
				"%s[%d]: смещение %.0f/%.0f/%.0f, половина размера %.0f/%.0f/%.0f -> %s",
				name, index, offset.X, offset.Y, offset.Z,
				box.Size.X / 2, box.Size.Y / 2, box.Size.Z / 2,
				isInsideBox(box, position) and "ВНУТРИ" or "снаружи"))
		end
	end
	report("SafeZone", safeZoneBoxes)
	for _, biome in ipairs(biomeOrder) do
		report(biome.Id, biome.Boxes)
	end
	return lines
end

---------------------------------------------------------------------
-- Safe zone
---------------------------------------------------------------------

function WorldService.HasSafeZone()
	return #safeZoneBoxes > 0
end

function WorldService.IsInSafeZone(position)
	if #safeZoneBoxes == 0 then
		return false -- safe zone не найдена: считаем, что её нет
	end
	return isInsideAny(safeZoneBoxes, position)
end

function WorldService.IsPlayerInSafeZone(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return WorldService.IsInSafeZone(root.Position)
end

---------------------------------------------------------------------
-- Биомы
---------------------------------------------------------------------

function WorldService.GetBiome(biomeId)
	return biomes[biomeId]
end

function WorldService.GetBiomes()
	return biomeOrder
end

-- В каком биоме находится точка (nil, если ни в одном)
function WorldService.GetBiomeAt(position)
	for _, biome in ipairs(biomeOrder) do
		if isInsideAny(biome.Boxes, position) then
			return biome
		end
	end
	return nil
end

function WorldService.GetPlayerBiome(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	return WorldService.GetBiomeAt(root.Position)
end

---------------------------------------------------------------------
-- Ворота
---------------------------------------------------------------------

-- Детали ворот. Заодно чиним типичную беду: незаякоренная деталь с выключенными
-- столкновениями просто проваливается сквозь пол, и к сбросу раунда показывать
-- уже нечего.
local function collectGateParts(gate, biomeId)
	local parts = {}
	if not gate then
		return parts
	end
	if gate:IsA("BasePart") then
		table.insert(parts, gate)
	else
		for _, descendant in ipairs(gate:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end
	local loose = 0
	for _, part in ipairs(parts) do
		if not part.Anchored then
			part.Anchored = true
			loose = loose + 1
		end
	end
	if loose > 0 then
		warn("[WorldService] Ворота биома " .. biomeId .. ": " .. loose
			.. " деталей были не заякорены, игра их заякорила. Поставь Anchored в Studio,"
			.. " иначе при открытии ворот они провалятся сквозь пол.")
	end
	if #parts == 0 then
		warn("[WorldService] У ворот биома " .. biomeId .. " нет ни одной детали")
	end
	-- Ворота во время спавна яиц закрыты и твёрдые: если их не исключить,
	-- яйца будут ложиться прямо на них, как на пол
	for _, part in ipairs(parts) do
		table.insert(ignoreParts, part)
	end
	return parts
end

local function setGate(parts, closed)
	for _, part in ipairs(parts) do
		-- Настоящую прозрачность запоминаем один раз, чтобы не испортить модель автора
		if part:GetAttribute("BaseTransparency") == nil then
			part:SetAttribute("BaseTransparency", part.Transparency)
		end
		if closed then
			local base = part:GetAttribute("BaseTransparency")
			part.Transparency = base >= 1 and GameConfig.Round.ClosedGateTransparency or base
			part.CanCollide = true
		else
			part.Transparency = 1
			part.CanCollide = false
		end
	end
end

function WorldService.SetGatesClosed(closed)
	local count = 0
	for _, biome in ipairs(biomeOrder) do
		setGate(biome.GateParts, closed)
		count = count + #biome.GateParts
	end
	print("[WorldService] Ворота " .. (closed and "закрыты" or "открыты") .. ", деталей: " .. count)
end

---------------------------------------------------------------------
-- Точки спавна яиц
---------------------------------------------------------------------

local function biomeBox(biome)
	return biome.Boxes[math.random(1, #biome.Boxes)]
end

-- Луч для поиска пола: пропускаем зоны, ворота, яйца, игроков
-- и вообще всё, у чего выключены столкновения.
local function groundParams(ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- невидимые хитбоксы без столкновений не считаются полом

	local filter = {}
	if ignore then
		table.insert(filter, ignore)
	end
	for _, part in ipairs(ignoreParts) do
		if part.Parent then
			table.insert(filter, part)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	params.FilterDescendantsInstances = filter
	return params
end

-- Ищет пол под точкой. Луч пускаем от потолка зоны и до самого низа,
-- чтобы он не начинался внутри высоких ворот.
local function groundUnder(box, x, z, ignore)
	local margin = GameConfig.Egg.SpawnHeightAbove
	local topY = (box.CFrame * CFrame.new(0, box.Size.Y / 2, 0)).Position.Y
	local from = Vector3.new(x, topY + margin, z)
	local distance = box.Size.Y + margin * 2
	local result = workspace:Raycast(from, Vector3.new(0, -distance, 0), groundParams(ignore))
	if result then
		return result.Position
	end
	return nil
end

-- Свободная точка для яйца. taken — уже занятые точки (Vector3).
function WorldService.FindEggSpawn(biome, taken, ignore)
	local minDistance = GameConfig.Egg.SpawnMinDistance

	local function isFree(point)
		for _, other in ipairs(taken) do
			if (Vector3.new(other.X, 0, other.Z) - Vector3.new(point.X, 0, point.Z)).Magnitude < minDistance then
				return false
			end
		end
		return true
	end

	-- Если автор расставил точки сам, берём их
	if #biome.Spawns > 0 then
		local shuffled = table.clone(biome.Spawns)
		for i = #shuffled, 2, -1 do
			local j = math.random(1, i)
			shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
		end
		for _, part in ipairs(shuffled) do
			if part.Parent and isFree(part.Position) then
				return part.Position
			end
		end
		-- Все точки заняты — ставим на первую свободную по порядку
		for _, part in ipairs(shuffled) do
			if part.Parent then
				return part.Position
			end
		end
	end

	-- Иначе случайная точка внутри биома с поиском пола
	local fallback
	for _ = 1, GameConfig.Egg.SpawnTries do
		local box = biomeBox(biome)
		local spot = (box.CFrame * CFrame.new(
			(math.random() - 0.5) * box.Size.X * 0.9,
			0,
			(math.random() - 0.5) * box.Size.Z * 0.9
		)).Position
		local ground = groundUnder(box, spot.X, spot.Z, ignore)
		if ground then
			fallback = fallback or ground
			if isFree(ground) then
				return ground
			end
		end
	end
	if not fallback then
		warn("[EggService] В биоме " .. biome.Id .. " не нашёлся пол под точками спавна."
			.. " Проверь, что пол биома — обычная деталь со столкновениями,"
			.. " либо расставь точки сам в папке EggSpawns.")
	end
	return fallback
end

---------------------------------------------------------------------
-- Чтение карты
---------------------------------------------------------------------

local function loadBiome(config, folder)
	local model = folder and folder:FindFirstChild(config.ModelName or config.Id)
	if not model then
		warn("[WorldService] Не найдена модель биома " .. config.Id
			.. ". Ожидается Workspace.Biomes." .. (config.ModelName or config.Id))
		return nil
	end

	local boxes = collectBoxes(model:FindFirstChild("Area", true) or model, "Area")
	if #boxes == 0 then
		warn("[WorldService] У биома " .. config.Id .. " не удалось определить границы")
		return nil
	end
	if not model:FindFirstChild("Area", true) then
		warn("[WorldService] У биома " .. config.Id .. " нет детали Area — границы взяты"
			.. " по габариту всей модели. Лучше добавить невидимую деталь Area.")
	end

	local spawns = {}
	local spawnFolder = model:FindFirstChild("EggSpawns", true)
	if spawnFolder then
		for _, child in ipairs(spawnFolder:GetDescendants()) do
			if child:IsA("BasePart") then
				table.insert(spawns, child)
			end
		end
	end

	local gate = model:FindFirstChild("Gate", true)
	if not gate then
		warn("[WorldService] У биома " .. config.Id .. " нет детали Gate — проход не будет закрываться")
	end

	return {
		Id = config.Id,
		Config = config,
		Model = model,
		Boxes = boxes,
		Gate = gate,
		GateParts = collectGateParts(gate, config.Id),
		Spawns = spawns,
	}
end

function WorldService.Init()
	local safeZone = workspace:FindFirstChild("SafeZone")
	safeZoneBoxes = collectBoxes(safeZone, "Area")
	if #safeZoneBoxes == 0 then
		warn("[WorldService] В Workspace нет SafeZone — яйца некуда будет доносить."
			.. " Сделай деталь или модель с именем SafeZone.")
	end

	local folder = workspace:FindFirstChild("Biomes")
	if not folder then
		warn("[WorldService] В Workspace нет папки Biomes — биомы не работают")
	end

	for _, config in ipairs(Biomes.List) do
		local biome = loadBiome(config, folder)
		if biome then
			biomes[biome.Id] = biome
			table.insert(biomeOrder, biome)
		end
	end

	WorldService.SetGatesClosed(false)
	print("[WorldService] Биомов найдено: " .. #biomeOrder
		.. ", safe zone: " .. (#safeZoneBoxes > 0 and "есть" or "НЕТ"))
end

return WorldService
