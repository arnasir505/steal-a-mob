-- PlotBuilder: всё, что связано с деталями участка в Workspace.
--
-- ВАЖНО про модели. Пока ты не сделал свои модели, этот файл строит временные
-- кубики, чтобы игру можно было проверить. Как только в игре появятся настоящие
-- модели, временные перестанут создаваться сами собой:
--
--   * Участки: положи в Workspace папку "Plots", а в неё модели "Plot1", "Plot2", ...
--     Внутри каждой модели: детали "Slot1", "Slot2", ... (куда встают яйца и мобы)
--     и деталь "Spawn" (где появляется хозяин участка). Деталь "Sign" — необязательно.
--   * Яйца: ReplicatedStorage.Assets.Eggs.<EggModelName> (см. Config/Mobs.luau)
--   * Мобы: ReplicatedStorage.Assets.Mobs.<ModelName>
--     У каждой модели обязательно должен быть выставлен PrimaryPart.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

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

-- Номер из имени "Slot12" -> 12
local function slotNumber(name)
	return tonumber(string.match(name, "^Slot(%d+)$"))
end

---------------------------------------------------------------------
-- Временный участок
---------------------------------------------------------------------

local function buildTempPlot(index, parent)
	local rows = math.ceil(GameConfig.Base.MaxSlots / P.SlotsPerRow)
	local width = P.SlotsPerRow * P.SlotSpacing + 8
	local depth = rows * P.SlotSpacing + 20
	-- Участки стоят в ряд и центрируются вокруг TempOrigin
	local offsetX = (index - 1 - (P.TempCount - 1) / 2) * P.TempSpacing
	local origin = P.TempOrigin + Vector3.new(offsetX, 0, 0)

	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	local floor = makePart("Floor", Vector3.new(width, 1, depth), CFrame.new(origin), Color3.fromRGB(90, 140, 80), model)
	model.PrimaryPart = floor

	-- Место появления хозяина — у ближнего края участка
	makePart("Spawn", Vector3.new(8, 1, 8), CFrame.new(origin + Vector3.new(0, 0.6, depth / 2 - 6)), Color3.fromRGB(230, 230, 230), model)

	-- Табличка с именем владельца
	makePart("Sign", Vector3.new(6, 1, 1), CFrame.new(origin + Vector3.new(0, 4, depth / 2 - 1)), Color3.fromRGB(120, 90, 60), model)

	-- Сетка слотов
	local gridCenterZ = origin.Z - 4
	local startX = origin.X - (P.SlotsPerRow - 1) * P.SlotSpacing / 2
	local startZ = gridCenterZ - (rows - 1) * P.SlotSpacing / 2
	for i = 1, GameConfig.Base.MaxSlots do
		local col = (i - 1) % P.SlotsPerRow
		local row = math.floor((i - 1) / P.SlotsPerRow)
		local position = Vector3.new(startX + col * P.SlotSpacing, origin.Y + 0.75, startZ + row * P.SlotSpacing)
		makePart("Slot" .. i, Vector3.new(P.SlotSize, 0.5, P.SlotSize), CFrame.new(position), Color3.fromRGB(150, 150, 150), model)
	end

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
		local number = tonumber(string.match(model.Name, "(%d+)$")) or math.huge
		table.insert(list, { Model = model, Number = number })
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

-- Детали Slot1..SlotN участка, по порядку номера
function PlotBuilder.GetSlotParts(plotModel)
	local parts = {}
	for _, descendant in ipairs(plotModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local number = slotNumber(descendant.Name)
			if number then
				parts[number] = descendant
			end
		end
	end
	return parts
end

-- Где появляется хозяин участка
function PlotBuilder.GetSpawnCFrame(plotModel)
	local spawnPart = plotModel:FindFirstChild("Spawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.CFrame + Vector3.new(0, spawnPart.Size.Y / 2 + 3, 0)
	end
	local ok, cframe = pcall(function()
		return plotModel:GetPivot()
	end)
	if ok then
		return cframe + Vector3.new(0, 5, 0)
	end
	return nil
end

---------------------------------------------------------------------
-- Табличка с именем владельца
---------------------------------------------------------------------

function PlotBuilder.SetSignText(plotModel, text)
	local sign = plotModel:FindFirstChild("Sign", true)
	if not sign or not sign:IsA("BasePart") then
		return
	end
	local gui = sign:FindFirstChild("PlotSign")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "PlotSign"
		gui.Size = UDim2.fromScale(10, 2)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 200

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.4
		label.Parent = gui

		gui.Parent = sign
	end
	gui.Label.Text = text
end

---------------------------------------------------------------------
-- Подпись над слотом (временный интерфейс до этапа 11)
---------------------------------------------------------------------

function PlotBuilder.EnsureSlotLabel(slotPart)
	local gui = slotPart:FindFirstChild("SlotInfo")
	if gui then
		return gui.Label
	end
	gui = Instance.new("BillboardGui")
	gui.Name = "SlotInfo"
	gui.Size = UDim2.fromScale(8, 2)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = gui

	gui.Parent = slotPart
	return label
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
	local mob = Mobs[item.MobId]
	local rarity = mob and Rarities.Data[mob.Rarity]
	local color = rarity and rarity.Color or Color3.fromRGB(200, 200, 200)

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

-- Готовая модель предмета для слота. kind = "Egg" или "Mob".
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
			local first = model:FindFirstChildWhichIsA("BasePart", true)
			model.PrimaryPart = first
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

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	return model
end

-- Ставит модель на слот и возвращает её
function PlotBuilder.ShowOnSlot(slotPart, model)
	PlotBuilder.ClearSlot(slotPart)
	if not model then
		return nil
	end
	local size = model:GetExtentsSize()
	local top = slotPart.Position.Y + slotPart.Size.Y / 2
	model:PivotTo(CFrame.new(slotPart.Position.X, top + size.Y / 2, slotPart.Position.Z))
	model.Name = "Display"
	model.Parent = slotPart
	return model
end

function PlotBuilder.ClearSlot(slotPart)
	local old = slotPart:FindFirstChild("Display")
	if old then
		old:Destroy()
	end
end

return PlotBuilder
