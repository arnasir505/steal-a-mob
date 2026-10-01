-- IndexWindow: индекс мобов.
--  * слева — биомы (картинка biome_<id> из UIAssets, например biome_plains);
--  * в центре — мобы выбранного биома. Модель показывается прямо из
--    ReplicatedStorage.Assets.Mobs; неоткрытый моб — чёрный силуэт и "???";
--  * справа — выбранный моб крупно и меч-награда за весь биом;
--  * снизу — сколько открыто в биоме и всего.
-- Список открытых мобов приходит с сервера (GetIndex), новые — сигналом IndexUpdated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Biomes = require(ReplicatedStorage.Shared.Config.Biomes)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)

local Kit = require(script.Parent.Kit)

local IndexWindow = {}

---------------------------------------------------------------------
-- 3D-превью моба
---------------------------------------------------------------------

-- Модель моба для превью. Нет модели — простой кубик.
local function mobModel(mobId)
	local mob = Mobs[mobId]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Mobs")
	local template = mob and folder and folder:FindFirstChild(mob.ModelName or mobId)
	if template and template:IsA("Model") then
		return template:Clone()
	end
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Size = Vector3.new(2, 2, 3)
	part.Color = Color3.fromRGB(230, 220, 200)
	part.Parent = model
	model.PrimaryPart = part
	return model
end

-- Рамка с 3D-моделью. silhouette = true — модель чёрная (моб ещё не открыт).
local function mobViewport(parent, mobId, silhouette, props)
	local viewport = Kit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1, -1),
		ImageColor3 = silhouette and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
		ImageTransparency = silhouette and 0.15 or 0,
		Active = false,
		ZIndex = props.ZIndex or 13,
		Parent = parent,
	})
	local model = mobModel(mobId)
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Камера спереди-сбоку-сверху. Лицо моба смотрит в -Z его PrimaryPart.
	local boxCFrame, size = model:GetBoundingBox()
	local front = model.PrimaryPart and model.PrimaryPart.CFrame or boxCFrame
	local direction = (front.LookVector + front.RightVector * 0.6 + Vector3.new(0, 0.45, 0)).Unit
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	camera.CFrame = CFrame.lookAt(boxCFrame.Position + direction * distance, boxCFrame.Position)
	return viewport
end

---------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------

local function biomeMobs(biomeId)
	return Formulas.BiomeMobIds(biomeId)
end

local function totalProgress(index)
	local opened, total = 0, 0
	for _, biome in ipairs(Biomes.List) do
		local o, t = Formulas.IndexProgress(index, biome.Id)
		opened = opened + o
		total = total + t
	end
	return opened, total
end

-- Полоска прогресса с надписью
local function progressBar(parent, props)
	local bar = Kit.new("Frame", {
		BackgroundColor3 = Kit.Colors.Black,
		BackgroundTransparency = 0.2,
		Size = props.Size,
		Position = props.Position,
		Active = false,
		ZIndex = 13,
		Parent = parent,
	})
	Kit.Corner(bar, 8)
	Kit.Stroke(bar, 3, Kit.Colors.Black, true)
	local fill = Kit.new("Frame", {
		BackgroundColor3 = props.Color,
		Size = UDim2.fromScale(0, 1),
		Active = false,
		ZIndex = 13,
		Parent = bar,
	})
	Kit.Corner(fill, 8)
	Kit.Gloss(fill, props.Color)
	local text = Kit.Text({ Size = UDim2.fromScale(0.9, 0.72), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), StrokeThickness = 4, ZIndex = 14, Parent = bar })
	return function(opened, total, label)
		fill.Size = UDim2.fromScale(total > 0 and opened / total or 0, 1)
		text.Text = (label or "") .. opened .. "/" .. total
	end
end

function IndexWindow.Build(screen)
	local window = Kit.Window(screen, { Name = "Index", Title = "Mob Index", Color = Kit.Colors.Blue })
	local body = window.Body

	local index = {}          -- [MobId] = true — открытые мобы
	local selectedBiome = Biomes.List[1] and Biomes.List[1].Id
	local selectedMob

	-- Слева: биомы
	local biomeList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1, Size = UDim2.new(0, 210, 1, -70), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ZIndex = 12, Parent = body,
	})
	Kit.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = biomeList })

	-- В центре: мобы биома
	local grid = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(226, 0), Size = UDim2.new(0, 610, 1, -140),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ZIndex = 12, Parent = body,
	})
	Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(140, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = grid })
	local setBiomeProgress = progressBar(body, { Size = UDim2.fromOffset(600, 56), Position = UDim2.new(0, 230, 1, -128), Color = Kit.Colors.Green })

	-- Справа: превью и награда
	local side = Kit.new("Frame", {
		BackgroundColor3 = Kit.Colors.Panel, Position = UDim2.new(1, -270, 0, 0), Size = UDim2.new(0, 270, 1, -70),
		Active = false, ZIndex = 12, Parent = body,
	})
	Kit.Corner(side, 8)
	Kit.Stroke(side, 3, Kit.Colors.Black, true)
	local previewHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 200), Active = false, ZIndex = 13, Parent = side })
	local mobName = Kit.Text({ Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0.5, 0, 0, 200), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 13, Parent = side })
	local mobInfo = Kit.Text({ Color = Kit.Colors.Money, Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0.5, 0, 0, 240), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 13, Parent = side })
	Kit.Text({ Text = "Biome reward:", Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0.5, 0, 0, 290), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 13, Parent = side })
	local rewardText = Kit.Text({ Color = Kit.Colors.Gold, Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0.5, 0, 0, 320), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 13, Parent = side })
	local rewardStatus = Kit.Text({ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0.5, 0, 0, 358), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 13, Parent = side })

	-- Снизу: всего открыто
	local setTotalProgress = progressBar(body, { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 1, -56), Color = Kit.Colors.Blue })

	local renderGrid, renderSide

	function renderSide()
		previewHolder:ClearAllChildren()
		local mob = selectedMob and Mobs[selectedMob]
		if not mob then
			mobName.Text = ""
			mobInfo.Text = ""
		else
			local opened = index[selectedMob]
			Kit.Glow({ Size = UDim2.fromOffset(330, 330), Transparency = opened and 0.3 or 0.65, ZIndex = 13, Parent = previewHolder })
			mobViewport(previewHolder, selectedMob, not opened, { Size = UDim2.fromScale(1, 1), ZIndex = 14 })
			mobName.Text = opened and (mob.DisplayName or selectedMob) or "???"
			mobInfo.Text = opened and ("Base income $" .. Format.Number(mob.BaseIncome) .. "/s") or "Hatch it to unlock"
		end

		local biome = Biomes.Get(selectedBiome)
		local sword = biome and biome.SwordReward and Items.Swords[biome.SwordReward]
		if sword then
			rewardText.Text = sword.DisplayName
			local opened, total = Formulas.IndexProgress(index, selectedBiome)
			rewardStatus.Text = opened >= total and "Received!" or ("Unlock all " .. total .. " mobs")
		else
			rewardText.Text = "No reward"
			rewardStatus.Text = ""
		end
	end

	function renderGrid()
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for order, mobId in ipairs(biomeMobs(selectedBiome)) do
			local opened = index[mobId]
			local card = Kit.new("TextButton", {
				Name = mobId, Text = "", AutoButtonColor = false, LayoutOrder = order,
				BackgroundColor3 = opened and Kit.Colors.Blue or Kit.Colors.Locked, ZIndex = 13, Parent = grid,
			})
			Kit.Corner(card, 8)
			Kit.Stroke(card, selectedMob == mobId and 4 or 3, selectedMob == mobId and Kit.Colors.White or Kit.Colors.Black, true)
			Kit.Gloss(card, card.BackgroundColor3)
			card.ClipsDescendants = true
			Kit.Glow({
				Size = UDim2.fromOffset(250, 250), Position = UDim2.new(0.5, 0, 0.5, 12),
				Transparency = opened and 0.3 or 0.65, ZIndex = 13, Parent = card,
			})
			mobViewport(card, mobId, not opened, { Size = UDim2.new(1, -10, 1, -36), Position = UDim2.fromOffset(5, 30), ZIndex = 14 })
			Kit.Text({
				Text = opened and (Mobs[mobId].DisplayName or mobId) or "???",
				Size = UDim2.new(1, -10, 0, 28), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 15, Parent = card,
			})
			card.Activated:Connect(function()
				selectedMob = mobId
				renderGrid()
				renderSide()
			end)
		end
		local opened, total = Formulas.IndexProgress(index, selectedBiome)
		setBiomeProgress(opened, total, "")
		setTotalProgress(totalProgress(index))
	end

	-- Кнопки биомов
	for order, biome in ipairs(Biomes.List) do
		local card = Kit.new("TextButton", {
			Name = biome.Id, Text = "", AutoButtonColor = false, LayoutOrder = order,
			BackgroundColor3 = Kit.Colors.Green, Size = UDim2.fromOffset(200, 300), ZIndex = 13, Parent = biomeList,
		})
		Kit.Corner(card, 8)
		Kit.Stroke(card, 4, Kit.Colors.Black, true)
		local image = Kit.Icon({ Image = "biome_" .. string.lower(biome.Id), Size = UDim2.fromScale(1, 1), ZIndex = 13, Parent = card })
		if image:IsA("ImageLabel") then
			image.ScaleType = Enum.ScaleType.Crop
			Kit.Corner(image, 8)
		end
		Kit.Text({ Text = biome.DisplayName or biome.Id, Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0), StrokeThickness = 4, ZIndex = 14, Parent = card })
		card.Activated:Connect(function()
			selectedBiome = biome.Id
			selectedMob = biomeMobs(biome.Id)[1]
			renderGrid()
			renderSide()
		end)
	end
	selectedMob = selectedBiome and biomeMobs(selectedBiome)[1]

	local function reload()
		local ok, result = pcall(function()
			return Remotes.Function("GetIndex"):InvokeServer()
		end)
		if ok and type(result) == "table" then
			index = result
		end
		if window.IsOpen() then
			renderGrid()
			renderSide()
		end
	end

	window.OnOpen(reload)
	Remotes.Event("IndexUpdated").OnClientEvent:Connect(function(mobId)
		index[mobId] = true
		if window.IsOpen() then
			renderGrid()
			renderSide()
		end
	end)

	return { Window = window }
end

return IndexWindow
