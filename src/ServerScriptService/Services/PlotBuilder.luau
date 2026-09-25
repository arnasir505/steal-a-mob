-- PlotBuilder: всё, что связано с деталями участка в Workspace.
--
-- ВАЖНО про модели. Пока ты не сделал свои модели, этот файл строит временные
-- кубики, чтобы игру можно было проверить. Как только появятся настоящие модели,
-- временные перестанут создаваться сами собой.
--
-- Что игра ждёт от модели участка (Workspace.Plots.Plot1, Plot2, ...):
--   Floor    — деталь-пол. По ней игра понимает границы участка: ставить яйца
--              можно только над ней. Обязательная деталь.
--   Spawn    — деталь, где появляется хозяин участка.
--   Sign     — необязательно. Имя владельца и число занятых мест.
--              Может быть деталью ИЛИ моделью. Если внутри есть своя надпись
--              (SurfaceGui с TextLabel по имени "Label"), игра пишет в неё.
--              Если своей надписи нет — вешает свою табличку над деталью.
--              То же правило у Upgrade и Treadmill.
--   Upgrade  — необязательно. Тумба, у которой покупают улучшение участка.
--              Если её нет, улучшение покупается у таблички Sign.
--   Treadmill— необязательно. Беговая дорожка: игрок встаёт на неё, прилипает,
--              бежит на месте и получает скорость. Спрыгивает пробелом.
--              Внутри можно сделать "Treadmill_Floor" (деталь или модель) —
--              это полотно, по нему считается, где стоит игрок и куда он смотрит.
--              Если его нет, берётся вся модель дорожки.
--              Необязательная деталь "Treadmill_Front" задаёт, куда лицом бежать;
--              без неё игрок встаёт вдоль длинной стороны полотна.
--   Fences   — необязательно. Папка с моделями заборов: Fence0, Fence3, Fence7...
--              Число в имени — с какого уровня улучшения показывать этот забор.
--              Если папки нет, игра строит простой забор из деталей сама.
--
-- Отдельных деталей под слоты БОЛЬШЕ НЕ НУЖНО: игрок ставит яйцо в любом
-- свободном месте участка, а уровень улучшения задаёт только число мест.
--
-- Модели яиц и мобов:
--   ReplicatedStorage.Assets.Eggs.<EggModelName>, .Mobs.<ModelName>
--   У каждой модели обязательно должен быть выставлен PrimaryPart.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)

local P = GameConfig.Plot

local PlotBuilder = {}

---------------------------------------------------------------------
-- Мелкие помощники
---------------------------------------------------------------------

local function makePart(name, size, cframe, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeLabel(parent, name, size, offset, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.AlwaysOnTop = false

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = gui

	gui.Parent = parent
	return label
end

-- Деталь, к которой можно прицепить табличку или подсказку.
-- Автор может сделать Sign, Upgrade или Treadmill не деталью, а моделью —
-- тогда берём её PrimaryPart (или первую деталь внутри).
function PlotBuilder.ResolvePart(holder)
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

---------------------------------------------------------------------
-- Границы участка
---------------------------------------------------------------------

-- Пол участка. По нему считаются границы.
function PlotBuilder.GetFloor(plotModel)
	local floor = plotModel:FindFirstChild("Floor", true) or plotModel:FindFirstChild("Area", true)
	if floor and floor:IsA("BasePart") then
		return floor
	end
	if plotModel:IsA("Model") and plotModel.PrimaryPart then
		return plotModel.PrimaryPart
	end
	return plotModel:FindFirstChildWhichIsA("BasePart", true)
end

-- Переводит мировую точку в координаты участка (x, z от центра пола)
function PlotBuilder.ToLocal(floor, worldPosition)
	local local3 = floor.CFrame:PointToObjectSpace(worldPosition)
	return local3.X, local3.Z
end

-- Помещается ли точка внутри участка с отступом от забора
function PlotBuilder.IsInside(floor, x, z)
	local halfX = floor.Size.X / 2 - P.PlaceMargin
	local halfZ = floor.Size.Z / 2 - P.PlaceMargin
	return math.abs(x) <= halfX and math.abs(z) <= halfZ
end

-- Загоняет точку внутрь участка (на случай, если участок оказался меньше)
function PlotBuilder.Clamp(floor, x, z)
	local halfX = math.max(0, floor.Size.X / 2 - P.PlaceMargin)
	local halfZ = math.max(0, floor.Size.Z / 2 - P.PlaceMargin)
	return math.clamp(x, -halfX, halfX), math.clamp(z, -halfZ, halfZ)
end

---------------------------------------------------------------------
-- Забор
---------------------------------------------------------------------

local function styleForLevel(level)
	local best = P.FenceStyles[1]
	for _, style in ipairs(P.FenceStyles) do
		if level >= style.MinLevel then
			best = style
		end
	end
	return best
end

-- Строит простой забор из столбиков по краю пола, с проходом у Spawn
local function buildSimpleFence(plotModel, floor, style)
	local old = plotModel:FindFirstChild("SimpleFence")
	if old then
		old:Destroy()
	end

	local fence = Instance.new("Model")
	fence.Name = "SimpleFence"

	local top = floor.Size.Y / 2
	local halfX, halfZ = floor.Size.X / 2, floor.Size.Z / 2
	local step = 4

	local function post(x, z)
		-- Проход у ближнего края (там, где Spawn)
		if z > halfZ - 0.1 and math.abs(x) < 6 then
			return
		end
		local cframe = floor.CFrame * CFrame.new(x, top + style.Height / 2, z)
		local part = makePart("Post", Vector3.new(0.6, style.Height, 0.6), cframe, style.Color, fence)
		part.Material = style.Material
		part.CanCollide = false
	end

	local x = -halfX
	while x <= halfX do
		post(x, -halfZ)
		post(x, halfZ)
		x = x + step
	end
	local z = -halfZ + step
	while z <= halfZ - step do
		post(-halfX, z)
		post(halfX, z)
		z = z + step
	end

	fence.Parent = plotModel
end

-- Показывает забор, который соответствует уровню участка
function PlotBuilder.UpdateFence(plotModel, level)
	local fences = plotModel:FindFirstChild("Fences")
	if fences then
		-- Свои модели автора: Fence0, Fence3, Fence7... показываем подходящую
		local bestChild, bestLevel
		for _, child in ipairs(fences:GetChildren()) do
			local minLevel = tonumber(string.match(child.Name, "(%d+)$"))
			if minLevel and level >= minLevel and (not bestLevel or minLevel > bestLevel) then
				bestChild, bestLevel = child, minLevel
			end
		end
		-- Показываем один забор, остальные прячем. Настоящую прозрачность
		-- детали запоминаем один раз, чтобы не испортить модель автора.
		for _, child in ipairs(fences:GetChildren()) do
			for _, part in ipairs(child:GetDescendants()) do
				if part:IsA("BasePart") then
					if part:GetAttribute("BaseTransparency") == nil then
						part:SetAttribute("BaseTransparency", part.Transparency)
					end
					part.Transparency = (child == bestChild) and part:GetAttribute("BaseTransparency") or 1
				end
			end
		end
		return
	end

	local floor = PlotBuilder.GetFloor(plotModel)
	if floor then
		buildSimpleFence(plotModel, floor, styleForLevel(level))
	end
end

---------------------------------------------------------------------
-- Временные участки
---------------------------------------------------------------------

local function buildTempPlot(index, parent)
	local size = P.TempFloorSize
	local offsetX = (index - 1 - (P.TempCount - 1) / 2) * P.TempSpacing
	local origin = P.TempOrigin + Vector3.new(offsetX, 0, 0)

	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	local floor = makePart("Floor", size, CFrame.new(origin), Color3.fromRGB(95, 145, 85), model)
	floor.Material = Enum.Material.Grass
	model.PrimaryPart = floor

	local top = origin.Y + size.Y / 2

	-- Место появления хозяина — у ближнего края, в проходе забора
	makePart("Spawn", Vector3.new(8, 0.2, 6), CFrame.new(origin.X, top + 0.1, origin.Z + size.Z / 2 - 4), Color3.fromRGB(235, 235, 235), model)

	-- Табличка с именем владельца
	makePart("Sign", Vector3.new(8, 1, 1), CFrame.new(origin.X, top + 4, origin.Z + size.Z / 2 + 1), Color3.fromRGB(120, 90, 60), model)

	-- Тумба улучшения участка
	-- Тумба стоит ЗА полом: её подсказка не должна мешать ставить яйца внутри
	local upgrade = makePart("Upgrade", Vector3.new(4, 3, 4), CFrame.new(origin.X + 8, top + 1.5, origin.Z + size.Z / 2 + 3), Color3.fromRGB(230, 180, 50), model)
	upgrade.Material = Enum.Material.Metal

	-- Беговая дорожка — тоже снаружи, чтобы не занимать место под яйца
	local treadmill = makePart("Treadmill", Vector3.new(6, 1, 10), CFrame.new(origin.X - 9, top, origin.Z + size.Z / 2 + 5), Color3.fromRGB(60, 60, 70), model)
	treadmill.Material = Enum.Material.DiamondPlate

	model.Parent = parent
	return model
end

-- Возвращает папку Workspace.Plots. Если её нет, строит временные участки.
function PlotBuilder.EnsurePlots()
	local existing = workspace:FindFirstChild("Plots")
	if existing then
		return existing, false
	end

	local folder = Instance.new("Folder")
	folder.Name = "Plots"
	for i = 1, P.TempCount do
		buildTempPlot(i, folder)
	end
	folder.Parent = workspace
	warn("[PlotBuilder] В Workspace нет папки Plots — построены временные участки (" .. P.TempCount .. " шт.)")
	return folder, true
end

-- Все участки по порядку номера в имени
function PlotBuilder.GetPlots(folder)
	local list = {}
	for _, model in ipairs(folder:GetChildren()) do
		table.insert(list, { Model = model, Number = tonumber(string.match(model.Name, "(%d+)$")) or math.huge })
	end
	table.sort(list, function(a, b)
		if a.Number == b.Number then
			return a.Model.Name < b.Model.Name
		end
		return a.Number < b.Number
	end)
	local result = {}
	for _, entry in ipairs(list) do
		table.insert(result, entry.Model)
	end
	return result
end

-- Где появляется хозяин участка
function PlotBuilder.GetSpawnCFrame(plotModel)
	local spawnPart = plotModel:FindFirstChild("Spawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.CFrame + Vector3.new(0, spawnPart.Size.Y / 2 + 3, 0)
	end
	local floor = PlotBuilder.GetFloor(plotModel)
	if floor then
		return floor.CFrame + Vector3.new(0, floor.Size.Y / 2 + 3, 0)
	end
	return nil
end

-- У какой детали покупают улучшение участка
function PlotBuilder.GetUpgradePart(plotModel)
	return PlotBuilder.ResolvePart(plotModel:FindFirstChild("Upgrade", true))
		or PlotBuilder.ResolvePart(plotModel:FindFirstChild("Sign", true))
end

-- Беговая дорожка участка
function PlotBuilder.GetTreadmill(plotModel)
	return PlotBuilder.ResolvePart(plotModel:FindFirstChild("Treadmill", true))
end

-- Поверхность дорожки: то, на чём стоит игрок.
-- Ищем внутри Treadmill деталь или модель "Treadmill_Floor"; если её нет,
-- берём саму дорожку. Модель из нескольких деталей тоже годится —
-- берём её общий габарит.
-- Возвращает { CFrame, Size, Forward } — Forward это длинная горизонтальная ось,
-- то есть направление бега.
function PlotBuilder.GetTreadmillSurface(plotModel)
	local treadmill = plotModel:FindFirstChild("Treadmill", true)
	if not treadmill then
		return nil
	end
	local surface = treadmill:FindFirstChild("Treadmill_Floor", true) or treadmill

	local cframe, size
	if surface:IsA("BasePart") then
		cframe, size = surface.CFrame, surface.Size
	elseif surface:IsA("Model") then
		cframe, size = surface:GetBoundingBox()
	else
		local part = PlotBuilder.ResolvePart(surface)
		if not part then
			return nil
		end
		cframe, size = part.CFrame, part.Size
	end

	-- Куда бежать: вдоль длинной стороны. Если автор положил внутрь деталь
	-- "Treadmill_Front", бежим в её сторону.
	local forward
	local front = treadmill:FindFirstChild("Treadmill_Front", true)
	local frontPart = front and PlotBuilder.ResolvePart(front)
	if frontPart then
		local direction = frontPart.Position - cframe.Position
		forward = Vector3.new(direction.X, 0, direction.Z)
	end
	if not forward or forward.Magnitude < 0.01 then
		forward = (size.Z >= size.X) and cframe.LookVector or cframe.RightVector
		forward = Vector3.new(forward.X, 0, forward.Z)
	end
	if forward.Magnitude < 0.01 then
		forward = Vector3.new(0, 0, 1)
	end

	return {
		CFrame = cframe,
		Size = size,
		Forward = forward.Unit,
		Part = PlotBuilder.ResolvePart(treadmill),
	}
end

-- Папка, куда складываются поставленные яйца и мобы
function PlotBuilder.EnsurePlacedFolder(plotModel)
	local folder = plotModel:FindFirstChild("Placed")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Placed"
		folder.Parent = plotModel
	end
	return folder
end

---------------------------------------------------------------------
-- Таблички
---------------------------------------------------------------------

-- Ищет готовую надпись автора внутри детали или модели.
-- Берём TextLabel с именем "Label"; если его нет, но TextLabel всего один —
-- берём его. Свои таблички мы тоже называем "Label", поэтому функция годится и для них.
local function findLabel(holder)
	if not holder then
		return nil
	end
	local named, single, count = nil, nil, 0
	for _, descendant in ipairs(holder:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			count = count + 1
			single = single or descendant
			if descendant.Name == "Label" then
				named = named or descendant
			end
		end
	end
	if named then
		return named
	end
	if count == 1 then
		return single
	end
	return nil
end

-- Пишет текст на табличку. Если автор сделал свою надпись (SurfaceGui с TextLabel) —
-- пишем в неё. Если нет — вешаем свою BillboardGui над деталью.
-- ownOnly = true: чужую надпись не трогать (чтобы две разные надписи не дрались за один TextLabel).
local function setLabelText(holder, guiName, text, size, offset, maxDistance, ownOnly)
	if not holder then
		return
	end
	local label = not ownOnly and findLabel(holder) or nil
	if not label then
		local part = PlotBuilder.ResolvePart(holder)
		if not part then
			return
		end
		local gui = part:FindFirstChild(guiName)
		label = gui and gui:FindFirstChild("Label")
		if not label then
			label = makeLabel(part, guiName, size, offset, maxDistance)
		end
	end
	label.Text = text
end

function PlotBuilder.SetSignText(plotModel, text)
	setLabelText(plotModel:FindFirstChild("Sign", true), "PlotSign",
		text, UDim2.fromScale(12, 2.5), Vector3.new(0, 2, 0), 250, false)
end

function PlotBuilder.SetUpgradeText(plotModel, text)
	local upgrade = plotModel:FindFirstChild("Upgrade", true)
	if upgrade then
		setLabelText(upgrade, "UpgradeSign", text, UDim2.fromScale(9, 2.5), Vector3.new(0, 3, 0), 120, false)
		return
	end
	-- Своей тумбы нет: пишем над табличкой Sign, но СВОЕЙ надписью,
	-- иначе затрём имя владельца.
	setLabelText(plotModel:FindFirstChild("Sign", true), "UpgradeSign",
		text, UDim2.fromScale(9, 2.5), Vector3.new(0, 5, 0), 120, true)
end

function PlotBuilder.SetTreadmillText(plotModel, text)
	setLabelText(plotModel:FindFirstChild("Treadmill", true), "TreadmillSign",
		text, UDim2.fromScale(9, 2.5), Vector3.new(0, 4, 0), 120, false)
end

-- Подпись над поставленным предметом
function PlotBuilder.EnsureItemLabel(model)
	local anchor = model.PrimaryPart
	if not anchor then
		return nil
	end
	local gui = anchor:FindFirstChild("ItemInfo")
	local label = gui and gui:FindFirstChild("Label")
	if label then
		return label
	end
	local height = model:GetExtentsSize().Y
	return makeLabel(anchor, "ItemInfo", UDim2.fromScale(8, 2), Vector3.new(0, height / 2 + 2.5, 0), 90)
end

---------------------------------------------------------------------
-- Модели яиц и мобов
---------------------------------------------------------------------

local function findTemplate(folderName, modelName)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(folderName)
	local template = folder and folder:FindFirstChild(modelName)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

-- Временная модель, пока автор не сделал свою
local function buildTempModel(item, kind)
	local color = Rarities.Get(item.Rarity).Color

	local model = Instance.new("Model")
	local part
	if kind == "Egg" then
		part = makePart("Body", Vector3.new(2, 2.6, 2), CFrame.new(), Color3.fromRGB(245, 240, 225), model)
		part.Shape = Enum.PartType.Ball
		-- Цветная "шапочка" подсказывает редкость яйца
		local cap = makePart("Cap", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.4, 0), color, model)
		cap.Shape = Enum.PartType.Ball
	else
		part = makePart("Body", Vector3.new(2, 2, 3), CFrame.new(), color, model)
		makePart("Head", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 0.8, -2), color, model)
	end
	model.PrimaryPart = part
	return model
end

-- Готовая модель предмета. kind = "Egg" или "Mob".
function PlotBuilder.MakeItemModel(item, kind)
	local mob = Mobs[item.MobId]
	local modelName
	if kind == "Egg" then
		modelName = mob and (mob.EggModelName or mob.ModelName)
	else
		modelName = mob and mob.ModelName
	end

	local model
	local template = modelName and findTemplate(kind == "Egg" and "Eggs" or "Mobs", modelName)
	if template then
		model = template:Clone()
		if not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
			warn("[PlotBuilder] У модели " .. modelName .. " не выставлен PrimaryPart")
		end
	else
		model = buildTempModel(item, kind)
	end

	if not model.PrimaryPart then
		model:Destroy()
		return nil
	end

	-- Размер растёт с весом медленно (логарифмически)
	local ok = pcall(function()
		model:ScaleTo(Formulas.ModelScale(item.Weight))
	end)
	if not ok then
		warn("[PlotBuilder] Не удалось изменить размер модели " .. tostring(modelName))
	end

	-- Мутация перекрашивает модель моба. Если у мутации убрать Color,
	-- модель останется такой, какой её сделал автор.
	local mutation = kind == "Mob" and Mutations.Get(item.Mutation) or nil

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			if mutation and mutation.Color then
				descendant.Color = mutation.Color
				descendant.Material = mutation.Material or descendant.Material
			end
		end
	end
	return model
end

-- Ставит модель на участок: x, z — координаты от центра пола, yaw — поворот
function PlotBuilder.PlaceModel(model, floor, x, z, yaw)
	local height = model:GetExtentsSize().Y
	local base = floor.CFrame * CFrame.new(x, floor.Size.Y / 2 + height / 2, z)
	model:PivotTo(base * CFrame.Angles(0, yaw or 0, 0))
end

return PlotBuilder
