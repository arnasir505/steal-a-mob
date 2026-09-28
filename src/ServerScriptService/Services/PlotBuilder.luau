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
--              У таблички же покупают улучшение участка: над ней висит цена.
--              Может быть деталью ИЛИ моделью. Если внутри есть своя надпись
--              (SurfaceGui с TextLabel по имени "Label"), игра пишет в неё.
--              Если своей надписи нет — вешает свою табличку над деталью.
--              То же правило у Treadmill.
--   Treadmill— необязательно. Беговая дорожка: игрок встаёт на неё, прилипает,
--              бежит на месте и получает скорость. Спрыгивает пробелом.
--              Внутри можно сделать "Treadmill_Floor" (деталь или модель) —
--              это полотно, по нему считается, где стоит игрок и куда он смотрит.
--              Если его нет, берётся вся модель дорожки.
--              Необязательная деталь "Treadmill_Front" задаёт, куда лицом бежать;
--              без неё игрок встаёт вдоль длинной стороны полотна.
--
-- Участок растёт с уровнем базы: передний край (где Spawn и табличка) на месте,
-- участок растёт назад и в стороны. Пол Floor растягивается сам.
--
-- Забор строится сам по всему периметру из звена забора:
--   ReplicatedStorage.Assets.Fences.<любое имя> — одно звено (модель или деталь).
--   Длинная сторона звена ляжет вдоль края, сторона Front — наружу.
--   Можно положить несколько звеньев с числом в имени: Fence0, Fence5, Fence10 —
--   число = с какого уровня базы использовать это звено (забор "красивеет").
-- Если звена нет, но в участке есть папка Fences с целыми заборами (Fence0, Fence3...),
-- показывается подходящий из них (под растущий участок это не подходит).
-- Если нет ни того, ни другого — игра ставит простые столбики.
--
-- Отдельных деталей под слоты БОЛЬШЕ НЕ НУЖНО: игрок ставит яйцо в любом
-- свободном месте участка, а уровень улучшения задаёт только число мест.
--
-- Модели яиц и мобов:
--   ReplicatedStorage.Assets.Eggs.<EggModelName>, .Mobs.<ModelName>
--   У каждой модели обязательно должен быть выставлен PrimaryPart.

local CollectionService = game:GetService("CollectionService")
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

---------------------------------------------------------------------
-- Только для хозяина
---------------------------------------------------------------------

-- Кнопки и надписи, которые видит только хозяин участка (Store/Sell, улучшения, цены).
-- Сервер создаёт их выключенными и помечает тегом, а клиент (OwnerOnly.client.luau)
-- включает у себя только то, что стоит на его участке. Хозяина клиент берёт
-- из атрибута OwnerUserId у модели участка (0 — участок свободен).
-- Нажать чужую кнопку всё равно нельзя: сервер сам проверяет, чей участок.
local OWNER_ONLY_TAG = "OwnerOnly"

-- Вызывать ДО того, как положить объект в участок: иначе чужие игроки
-- на мгновение увидят его включённым
function PlotBuilder.MakeOwnerOnly(instance)
	instance.Enabled = false
	CollectionService:AddTag(instance, OWNER_ONLY_TAG)
end

function PlotBuilder.SetPlotOwner(plotModel, player)
	plotModel:SetAttribute("OwnerUserId", player and player.UserId or 0)
end

local function makeLabel(parent, name, size, offset, maxDistance, ownerOnly)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.AlwaysOnTop = false
	gui:SetAttribute("GameLabel", true) -- своя надпись игры, не автора (см. findLabel)

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

	if ownerOnly then
		PlotBuilder.MakeOwnerOnly(gui)
	end
	gui.Parent = parent
	return label
end

-- Деталь, к которой можно прицепить табличку или подсказку.
-- Автор может сделать Sign или Treadmill не деталью, а моделью —
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
-- Границы участка и его рост
---------------------------------------------------------------------
--
-- Участок растёт с уровнем базы: передний край (где Spawn и табличка) стоит
-- на месте, а участок растёт назад и в стороны — на звено забора за уровень
-- (GameConfig.Plot: GrowDepthSegments, GrowSideSegments, GrowMaxLevel).
--
-- Размер на уровне 0 — пол Floor, как он сделан в Studio. Координаты
-- поставленных яиц и мобов считаются от ЭТОГО исходного пола ("якорь"),
-- поэтому, когда пол растёт и сдвигается, предметы остаются на своих местах.

-- Пол участка
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

-- Переводит мировую точку в координаты участка (x, z от центра якоря)
function PlotBuilder.ToLocal(anchor, worldPosition)
	local local3 = anchor.CFrame:PointToObjectSpace(worldPosition)
	return local3.X, local3.Z
end

-- Габарит модели или детали: CFrame центра и размер
local function boxOf(instance)
	if instance:IsA("Model") then
		local ok, cframe, size = pcall(function()
			return instance:GetBoundingBox()
		end)
		if ok then
			return cframe, size
		end
		return instance:GetPivot(), Vector3.zero
	end
	return instance.CFrame, instance.Size
end

-- Звено забора: где у него центр относительно точки привязки, какая сторона длинная
-- и какой он толщины
local function segmentInfo(template)
	local boxCFrame, size = boxOf(template)
	local info = {
		Template = template,
		PivotToBox = template:GetPivot():ToObjectSpace(boxCFrame),
		Turn = CFrame.new(),
		Length = size.X,
		Thickness = size.Z,
		Height = size.Y,
	}
	-- Длинная сторона вдоль Z — считаем звено повёрнутым на 90°, чтобы она шла вдоль X
	if size.Z > size.X then
		info.Turn = CFrame.Angles(0, math.rad(90), 0)
		info.Length = size.Z
		info.Thickness = size.X
	end
	return info
end

-- Звенья забора из ReplicatedStorage.Assets.Fences (читаются один раз).
-- Число в конце имени — с какого уровня базы звено используется (Fence0, Fence5...);
-- без числа — с уровня 0. Если звено одно, оно на всех уровнях.
local segmentCache

local function segments()
	if segmentCache then
		return segmentCache
	end
	segmentCache = {}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Fences")
	for _, child in ipairs(folder and folder:GetChildren() or {}) do
		if child:IsA("Model") or child:IsA("BasePart") then
			local info = segmentInfo(child)
			if info.Length >= 1 then
				info.MinLevel = tonumber(string.match(child.Name, "(%d+)$")) or 0
				table.insert(segmentCache, info)
			else
				warn("[PlotBuilder] Звено забора " .. child:GetFullName() .. " слишком короткое или пустое — пропускаем")
			end
		end
	end
	return segmentCache
end

-- Звено для уровня: с самым большим числом, до которого база доросла
local function pickSegment(level)
	local best, lowest
	for _, info in ipairs(segments()) do
		if level >= info.MinLevel and (not best or info.MinLevel > best.MinLevel) then
			best = info
		end
		if not lowest or info.MinLevel < lowest.MinLevel then
			lowest = info
		end
	end
	return best or lowest
end

-- Шаг роста: длина звена уровня 0 (или GrowStep, если звеньев нет)
local function growStep()
	local info = pickSegment(0)
	return info and info.Length or P.GrowStep
end

local POST_THICKNESS = 0.6 -- толщина столбиков простого забора

-- Насколько центр забора отступает внутрь от края пола: пол выступает
-- за внешнюю сторону забора на FloorOverhang студов
local function fenceInset(info)
	local thickness = info and info.Thickness or POST_THICKNESS
	return P.FloorOverhang + thickness / 2
end

-- До какого уровня участок растёт
local function growLevel(level)
	return math.clamp(level, 0, math.min(P.GrowMaxLevel, Formulas.MaxBaseLevel()))
end

-- Прямоугольник участка на уровне level в осях Frame (его +Z смотрит на вход):
-- minX, maxX, minZ, maxZ. Передний край (maxZ) стоит на месте.
local function bounds(shape, level)
	local step = growStep()
	local grow = growLevel(level)
	local side = grow * P.GrowSideSegments * step
	local depth = grow * P.GrowDepthSegments * step
	return -shape.HalfX - side, shape.HalfX + side, -shape.HalfZ - depth, shape.HalfZ
end

local shapes = {} -- [plotModel] = форма участка

-- Форма участка: исходный пол, где вход и размер на уровне 0.
-- Запоминается один раз, ДО того как пол начнёт расти.
local function getShape(plotModel)
	local shape = shapes[plotModel]
	if shape then
		return shape
	end
	local floor = PlotBuilder.GetFloor(plotModel)
	if not floor then
		return nil
	end
	local cf = floor.CFrame
	local halfX, halfZ = floor.Size.X / 2, floor.Size.Z / 2

	-- Где вход: сторона пола, ближайшая к Spawn (или к табличке).
	-- Frame поворачиваем так, чтобы его +Z смотрел на вход.
	local angle = 0
	local marker = PlotBuilder.ResolvePart(plotModel:FindFirstChild("Spawn", true))
		or PlotBuilder.ResolvePart(plotModel:FindFirstChild("Sign", true))
	if marker then
		local p = cf:PointToObjectSpace(marker.Position)
		if math.abs(p.X) / halfX > math.abs(p.Z) / halfZ then
			angle = p.X > 0 and 90 or -90
		else
			angle = p.Z >= 0 and 0 or 180
		end
	end
	local sideways = angle == 90 or angle == -90

	shape = {
		Floor = floor,
		-- Якорь: исходный пол. Похож на деталь (есть CFrame и Size), поэтому
		-- годится для ToLocal и PlaceModel
		Anchor = { CFrame = cf, Size = floor.Size },
		Frame = cf * CFrame.Angles(0, math.rad(angle), 0),
		HalfX = sideways and halfZ or halfX,
		HalfZ = sideways and halfX or halfZ,
		SizeY = floor.Size.Y,
	}
	shapes[plotModel] = shape

	-- Подсказка автору: насколько вырастет участок, чтобы оставить место между участками
	local minX, maxX, minZ, maxZ = bounds(shape, math.huge)
	print(string.format("[PlotBuilder] %s: пол %.0f x %.0f, на максимуме %.0f x %.0f (вширь x вглубь, шаг %.1f)",
		plotModel.Name, shape.HalfX * 2, shape.HalfZ * 2, maxX - minX, maxZ - minZ, growStep()))

	-- И какого размера сделать пол, чтобы звенья вставали ровно, без нахлёста
	local info = pickSegment(0)
	if info then
		local inset = fenceInset(info)
		local function ideal(length)
			local count = math.max(1, math.floor((length - 2 * inset) / info.Length + 0.5))
			return count * info.Length + 2 * inset
		end
		local idealX, idealZ = ideal(shape.HalfX * 2), ideal(shape.HalfZ * 2)
		if math.abs(idealX - shape.HalfX * 2) > 0.05 or math.abs(idealZ - shape.HalfZ * 2) > 0.05 then
			print(string.format("[PlotBuilder] %s: чтобы звенья забора встали ровно, сделай Floor %.2f x %.2f"
				.. " (вширь x вглубь, звено %.2f, толщина %.2f)",
				plotModel.Name, idealX, idealZ, info.Length, info.Thickness))
		end
	end
	return shape
end

-- Якорь участка — исходный пол из Studio. От него считаются координаты предметов.
function PlotBuilder.GetAnchor(plotModel)
	local shape = getShape(plotModel)
	return shape and shape.Anchor
end

-- Помещается ли точка (x, z от якоря) внутри участка уровня level с отступом от забора
function PlotBuilder.IsInsidePlot(plotModel, level, x, z)
	local shape = getShape(plotModel)
	if not shape then
		return false
	end
	local world = shape.Anchor.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
	local p = shape.Frame:PointToObjectSpace(world)
	local minX, maxX, minZ, maxZ = bounds(shape, level)
	-- Отступ считаем от ВНУТРЕННЕЙ стороны забора: край пола, свес пола, толщина забора
	local info = pickSegment(level)
	local margin = fenceInset(info) + (info and info.Thickness or POST_THICKNESS) / 2 + P.PlaceMargin
	return p.X >= minX + margin and p.X <= maxX - margin
		and p.Z >= minZ + margin and p.Z <= maxZ - margin
end

-- Пол растягивается на весь участок текущего уровня
local function resizeFloor(shape, minX, maxX, minZ, maxZ)
	local floor = shape.Floor
	floor.Size = Vector3.new(maxX - minX, shape.SizeY, maxZ - minZ)
	floor.CFrame = shape.Frame * CFrame.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
end

---------------------------------------------------------------------
-- Забор
---------------------------------------------------------------------

-- Стороны участка в осях Frame: откуда, куда и в какую сторону "наружу"
local function sides(minX, maxX, minZ, maxZ)
	return {
		{ From = Vector3.new(minX, 0, maxZ), To = Vector3.new(maxX, 0, maxZ), Out = Vector3.new(0, 0, 1) },  -- перед
		{ From = Vector3.new(maxX, 0, minZ), To = Vector3.new(minX, 0, minZ), Out = Vector3.new(0, 0, -1) }, -- зад
		{ From = Vector3.new(minX, 0, minZ), To = Vector3.new(minX, 0, maxZ), Out = Vector3.new(-1, 0, 0) }, -- левый бок
		{ From = Vector3.new(maxX, 0, maxZ), To = Vector3.new(maxX, 0, minZ), Out = Vector3.new(1, 0, 0) },  -- правый бок
	}
end

-- Забор из звеньев автора по всему периметру. Звенья идут вплотную; если сторона
-- не делится на длину звена ровно, звенья чуть заходят друг на друга — без щелей.
local function buildSegmentFence(plotModel, shape, info, minX, maxX, minZ, maxZ)
	local fence = Instance.new("Model")
	fence.Name = "AutoFence"
	local up = Vector3.yAxis
	local top = shape.SizeY / 2 -- верх пола в осях Frame
	for _, side in ipairs(sides(minX, maxX, minZ, maxZ)) do
		local length = (side.To - side.From).Magnitude
		local count = math.max(1, math.ceil(length / info.Length - 0.01))
		local step = length / count
		local along = (side.To - side.From).Unit
		for i = 1, count do
			local center = side.From + along * (step * (i - 0.5)) + Vector3.new(0, top + info.Height / 2, 0)
			-- Длинная сторона звена — вдоль края, лицевая сторона (Front) — наружу
			local target = CFrame.fromMatrix(center, up:Cross(-side.Out), up, -side.Out)
			local box = shape.Frame * target * info.Turn:Inverse()
			local segment = info.Template:Clone()
			segment:PivotTo(box * info.PivotToBox:Inverse())
			for _, part in ipairs(segment:IsA("BasePart") and { segment } or segment:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			segment.Parent = fence
		end
	end
	fence.Parent = plotModel
	return fence
end

local function styleForLevel(level)
	local best = P.FenceStyles[1]
	for _, style in ipairs(P.FenceStyles) do
		if level >= style.MinLevel then
			best = style
		end
	end
	return best
end

-- Простой забор из столбиков по краю участка (пока нет своего звена)
local function buildSimpleFence(plotModel, shape, style, minX, maxX, minZ, maxZ)
	local fence = Instance.new("Model")
	fence.Name = "SimpleFence"
	local top = shape.SizeY / 2
	local spacing = 4
	for _, side in ipairs(sides(minX, maxX, minZ, maxZ)) do
		local length = (side.To - side.From).Magnitude
		local count = math.max(1, math.floor(length / spacing))
		for i = 0, count - 1 do
			local point = side.From + (side.To - side.From) * (i / count)
			local cframe = shape.Frame * CFrame.new(point + Vector3.new(0, top + style.Height / 2, 0))
			local part = makePart("Post", Vector3.new(0.6, style.Height, 0.6), cframe, style.Color, fence)
			part.Material = style.Material
			part.CanCollide = false
		end
	end
	fence.Parent = plotModel
	return fence
end

-- Старый способ: целые заборы автора внутри участка (папка Fences: Fence0, Fence3...).
-- Под растущий участок не подходит — оставлен на случай, если звена нет.
-- [plotModel] = { Folder, List = { { Fence, MinLevel } } }. Список запоминаем один раз:
-- спрятанный забор лежит вне папки Fences, и найти его там уже нельзя.
local fenceSets = {}

local function getFenceSet(plotModel)
	local set = fenceSets[plotModel]
	if set then
		return set
	end
	local folder = plotModel:FindFirstChild("Fences")
	if not folder then
		return nil
	end

	set = { Folder = folder, List = {} }
	local hasStart = false
	for _, child in ipairs(folder:GetChildren()) do
		local minLevel = tonumber(string.match(child.Name, "(%d+)$"))
		if minLevel then
			table.insert(set.List, { Fence = child, MinLevel = minLevel })
			hasStart = hasStart or minLevel == 0
		else
			warn("[PlotBuilder] " .. child:GetFullName() .. ": в имени забора нет числа уровня"
				.. " (нужно Fence0, Fence3...). Этот забор будет виден всегда.")
		end
	end
	if #set.List > 0 and not hasStart then
		warn("[PlotBuilder] В " .. folder:GetFullName() .. " нет Fence0 — на уровне 0 у участка не будет забора")
	end
	fenceSets[plotModel] = set
	return set
end

-- Подгоняет участок под уровень базы: растит пол и строит забор по периметру.
-- Забор перестраивается, только если размер или звено поменялись.
function PlotBuilder.UpdateFence(plotModel, level)
	local shape = getShape(plotModel)
	if not shape then
		return
	end
	local minX, maxX, minZ, maxZ = bounds(shape, level)
	resizeFloor(shape, minX, maxX, minZ, maxZ)

	local info = pickSegment(level)
	local set = not info and getFenceSet(plotModel)
	if set and #set.List > 0 then
		-- Свои целые заборы автора: Fence0, Fence3, Fence7... Берём тот, у которого
		-- число самое большое, но не больше уровня участка. Остальные убираем из мира.
		local best
		for _, entry in ipairs(set.List) do
			if level >= entry.MinLevel and (not best or entry.MinLevel > best.MinLevel) then
				best = entry
			end
		end
		for _, entry in ipairs(set.List) do
			entry.Fence.Parent = (entry == best) and set.Folder or nil
		end
		return
	end

	if info then
		-- Забор строится сам из звена — старые заборы внутри участка больше не нужны
		local oldFolder = plotModel:FindFirstChild("Fences")
		if oldFolder then
			oldFolder.Parent = nil
			warn("[PlotBuilder] " .. plotModel.Name .. ": забор теперь строится сам из звена"
				.. " в ReplicatedStorage.Assets.Fences — удали папку Fences из участка в Studio")
		end
	end

	local style = styleForLevel(level)
	local key = (info and info.Template:GetFullName() or ("posts" .. style.MinLevel))
		.. string.format("|%.2f|%.2f|%.2f|%.2f", minX, maxX, minZ, maxZ)
	if shape.FenceKey == key and shape.Fence and shape.Fence.Parent then
		return
	end
	if shape.Fence then
		shape.Fence:Destroy()
	end
	-- Забор стоит внутри пола: пол выступает за его внешнюю сторону на FloorOverhang
	local inset = fenceInset(info)
	local fMinX, fMaxX, fMinZ, fMaxZ = minX + inset, maxX - inset, minZ + inset, maxZ - inset
	if info then
		shape.Fence = buildSegmentFence(plotModel, shape, info, fMinX, fMaxX, fMinZ, fMaxZ)
	else
		shape.Fence = buildSimpleFence(plotModel, shape, style, fMinX, fMaxX, fMinZ, fMaxZ)
	end
	shape.FenceKey = key
end

-- Самый широкий участок на максимальном уровне (для расстановки временных участков)
local function maxGrowWidth(floorWidth)
	return floorWidth + 2 * growLevel(math.huge) * P.GrowSideSegments * growStep()
end

---------------------------------------------------------------------
-- Временные участки
---------------------------------------------------------------------

local function buildTempPlot(index, parent, spacing)
	local size = P.TempFloorSize
	local offsetX = (index - 1 - (P.TempCount - 1) / 2) * spacing
	local origin = P.TempOrigin + Vector3.new(offsetX, 0, 0)

	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	local floor = makePart("Floor", size, CFrame.new(origin), Color3.fromRGB(95, 145, 85), model)
	floor.Material = Enum.Material.Grass
	model.PrimaryPart = floor

	local top = origin.Y + size.Y / 2

	-- Место появления хозяина — у ближнего края, в проходе забора
	makePart("Spawn", Vector3.new(8, 0.2, 6), CFrame.new(origin.X, top + 0.1, origin.Z + size.Z / 2 - 4), Color3.fromRGB(235, 235, 235), model)

	-- Табличка с именем владельца. У неё же покупают улучшение участка.
	-- Стоит ЗА полом: её подсказка не должна мешать ставить яйца внутри.
	makePart("Sign", Vector3.new(8, 1, 1), CFrame.new(origin.X, top + 4, origin.Z + size.Z / 2 + 1), Color3.fromRGB(120, 90, 60), model)

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
	-- Участки растут вширь: ставим их так, чтобы и на максимуме не наезжали друг на друга
	local spacing = math.max(P.TempSpacing, maxGrowWidth(P.TempFloorSize.X) + 6)
	for i = 1, P.TempCount do
		buildTempPlot(i, folder, spacing)
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

-- У какой детали покупают улучшение участка: у таблички Sign
function PlotBuilder.GetUpgradePart(plotModel)
	return PlotBuilder.ResolvePart(plotModel:FindFirstChild("Sign", true))
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
		-- Надписи, которые повесила сама игра, — не авторские, пропускаем
		if descendant:IsA("TextLabel") and not descendant.Parent:GetAttribute("GameLabel") then
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
-- ownerOnly = true: надпись видит только хозяин участка (см. MakeOwnerOnly).
local function setLabelText(holder, guiName, text, size, offset, maxDistance, ownOnly, ownerOnly)
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
			label = makeLabel(part, guiName, size, offset, maxDistance, ownerOnly)
		end
	end
	label.Text = text
end

function PlotBuilder.SetSignText(plotModel, text)
	setLabelText(plotModel:FindFirstChild("Sign", true), "PlotSign",
		text, UDim2.fromScale(12, 2.5), Vector3.new(0, 2, 0), 250, false)
end

-- Цена улучшения висит над табличкой Sign. Пишем СВОЕЙ надписью,
-- а не в надпись автора на табличке, иначе затрём имя владельца.
-- Видит её только хозяин участка.
function PlotBuilder.SetUpgradeText(plotModel, text)
	setLabelText(plotModel:FindFirstChild("Sign", true), "UpgradeSign",
		text, UDim2.fromScale(9, 2.5), Vector3.new(0, 5, 0), 120, true, true)
end

-- text — уровень и прибавка скорости (видят все),
-- upgradeText — цена улучшения над ними (видит только хозяин)
function PlotBuilder.SetTreadmillText(plotModel, text, upgradeText)
	local treadmill = plotModel:FindFirstChild("Treadmill", true)
	setLabelText(treadmill, "TreadmillSign",
		text, UDim2.fromScale(9, 2.5), Vector3.new(0, 4, 0), 120, false)
	setLabelText(treadmill, "TreadmillUpgrade",
		upgradeText or "", UDim2.fromScale(9, 1), Vector3.new(0, 5.9, 0), 120, true, true)
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
	-- Высоту подписи считаем от настоящего верха модели: PrimaryPart может быть
	-- где угодно, и подпись оказалась бы в ногах или в небе
	local boxCFrame, boxSize = model:GetBoundingBox()
	local above = (boxCFrame.Position.Y + boxSize.Y / 2) - anchor.Position.Y + 2
	-- Над гигантским мобом подпись висит высоко: делаем её крупнее
	-- и видимой издалека, иначе с земли её не прочитать
	local grow = math.max(1, boxSize.Y / 12)
	return makeLabel(anchor, "ItemInfo", UDim2.fromScale(8 * grow, 2 * grow),
		Vector3.new(0, above, 0), 90 + boxSize.Y)
end

-- Точка для кнопок Store/Sell: у земли, в центре модели. У гигантского моба
-- центр высоко в воздухе, и до кнопок на нём было бы не дотянуться.
-- Возвращает Attachment и дальность кнопок.
function PlotBuilder.MakePromptAnchor(model)
	local anchor = model.PrimaryPart
	local boxCFrame, boxSize = model:GetBoundingBox()
	local base = Vector3.new(boxCFrame.Position.X, boxCFrame.Position.Y - boxSize.Y / 2 + 2, boxCFrame.Position.Z)

	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAnchor"
	attachment.Position = anchor.CFrame:PointToObjectSpace(base)
	attachment.Parent = anchor

	-- Модели мобов без столкновений, так что к центру большого моба можно подойти.
	-- Но слишком большая дальность мешала бы ставить яйца рядом: пока видна
	-- чья-то кнопка, E значит "убрать", а не "поставить".
	local radius = math.max(boxSize.X, boxSize.Z) / 2
	local reach = P.ItemPromptDistance + math.min(radius, P.ItemPromptExtraMax)
	return attachment, reach
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

	-- Размер растёт с весом медленно (логарифмически).
	-- Умножаем на текущий масштаб модели: если автор увеличил её инструментом
	-- Scale в Studio, ScaleTo(1) вернул бы исходный размер и сбросил его работу.
	local scale
	if kind == "Egg" then
		scale = Formulas.EggModelScale(item.Weight, mob and mob.EggScale)
	else
		scale = Formulas.ModelScale(item.Weight, mob and mob.Scale)
	end
	local ok = pcall(function()
		model:ScaleTo(model:GetScale() * scale)
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

-- Ставит модель так, чтобы её НИЖНЯЯ ГРАНЬ стояла ровно на высоте groundY.
--
-- Почему нельзя просто поднять на половину высоты: PivotTo двигает точку привязки
-- модели (её PrimaryPart), а он может быть где угодно — в голове, в лапе, сбоку.
-- Поэтому сначала ставим модель с нужным поворотом, потом меряем, где у неё
-- на самом деле низ, и поднимаем ровно на разницу.
local function restOnGround(model, cframe, groundY)
	model:PivotTo(cframe)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - bottom, 0))
end

-- Ставит модель на участок: x, z — координаты от центра пола, yaw — поворот
function PlotBuilder.PlaceModel(model, floor, x, z, yaw)
	local groundY = (floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)).Position.Y
	local spot = (floor.CFrame * CFrame.new(x, 0, z)).Position
	local rotation = floor.CFrame - floor.CFrame.Position
	restOnGround(model, CFrame.new(spot) * rotation * CFrame.Angles(0, yaw or 0, 0), groundY)
end

-- Ставит модель на землю в мировой точке (яйца в биомах)
function PlotBuilder.PlaceOnGround(model, position, yaw)
	restOnGround(model, CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0), position.Y)
end

-- Ставит модель так, чтобы её ЦЕНТР оказался в точке (яйцо над головой игрока)
function PlotBuilder.CenterAt(model, position)
	model:PivotTo(CFrame.new(position))
	local boxCFrame = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + (position - boxCFrame.Position))
end

return PlotBuilder
