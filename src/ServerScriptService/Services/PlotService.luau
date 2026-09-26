-- PlotService: участки игроков.
--
-- Как устроен участок:
--  * участок огорожен забором, внутри — свободное место;
--  * яйцо или моба можно поставить В ЛЮБОЕ свободное место внутри забора;
--  * "слоты" — это вместимость участка, а не плитки на земле;
--  * улучшение участка покупается целиком: даёт сразу несколько мест
--    и делает забор красивее.
--
-- Что делает сервис:
--  * выдаёт свободный участок при входе и освобождает при выходе;
--  * ставит, убирает и продаёт яйца и мобов;
--  * вылупляет яйца (в том числе пока игрок был офлайн — время хранится как дата конца);
--  * считает доход в секунду и начисляет деньги.
--
-- Управление (настоящий интерфейс будет на этапе 11):
--   E на свободном месте участка — поставить яйцо из рюкзака
--   E у предмета — убрать его в рюкзак
--   F у предмета — продать
--   E у тумбы улучшения — расширить участок

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PassService = require(script.Parent.PassService)
local SpeedService = require(script.Parent.SpeedService)
local PlotBuilder = require(script.Parent.PlotBuilder)

local PlotService = {}

local rng = Random.new()

local plots = {}      -- список участков
local byPlayer = {}   -- [player] = участок
local lastPlaceAt = {} -- [player] = время последней постановки

---------------------------------------------------------------------
-- Данные участка
---------------------------------------------------------------------

local function capacity(data)
	return Formulas.BaseSlots(data.BaseLevel)
end

local function countItems(data)
	local n = 0
	for _ in pairs(data.Plot.Items) do
		n = n + 1
	end
	return n
end

local function itemName(item)
	local mob = Mobs[item.MobId]
	return mob and mob.DisplayName or item.MobId
end

local function hatchMultiplier(player)
	return PassService.Has(player, "X2Hatch") and 2 or 1
end

-- Старые сохранения: раньше предметы стояли на плитках Slot1..SlotN.
-- Переносим их на свободные места, чтобы прогресс не пропал.
local function migrateOldSlots(data)
	local old = data.Plot.Slots
	if type(old) ~= "table" or next(old) == nil then
		data.Plot.Slots = nil
		return
	end
	local index = 0
	for _, slot in pairs(old) do
		local id = tostring(data.NextItemId or 1)
		data.NextItemId = (data.NextItemId or 1) + 1
		slot.X = -12 + (index % 5) * 6
		slot.Z = -12 + math.floor(index / 5) * 6
		slot.R = 0
		data.Plot.Items[id] = slot
		index = index + 1
	end
	data.Plot.Slots = nil
	warn("[PlotService] Старые слоты перенесены на свободные места: " .. index .. " шт.")
end

---------------------------------------------------------------------
-- Доход
---------------------------------------------------------------------

local function recalcIncome(player)
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local income = EconomyService.CalculateBaseIncome(data) * EconomyService.GetMoneyMultiplier(player)
	EconomyService.SetIncomePerSecond(player, income)
	return income
end

PlotService.RecalcIncome = recalcIncome

---------------------------------------------------------------------
-- Показ предметов
---------------------------------------------------------------------

local function labelFor(placed)
	if placed.Type == "Egg" then
		local left = math.max(0, (placed.HatchEndsAt or 0) - os.time())
		return Rarities.Get(placed.Item.Rarity).DisplayName .. " " .. itemName(placed.Item) .. " Egg\n" .. Format.Time(left)
	end
	return InventoryService.Describe(placed.Item) .. "\n$" .. Format.Number(Formulas.MobIncome(placed.Item)) .. "/s"
end

local function clearItemVisual(entry, id)
	local model = entry.Models[id]
	if model then
		model:Destroy()
	end
	entry.Models[id] = nil
	entry.Labels[id] = nil
end

-- Создаёт модель предмета на участке вместе с подсказками
local function renderItem(entry, id, placed)
	clearItemVisual(entry, id)

	local model = PlotBuilder.MakeItemModel(placed.Item, placed.Type)
	if not model then
		return
	end
	model.Name = id
	PlotBuilder.PlaceModel(model, entry.Floor, placed.X or 0, placed.Z or 0, placed.R or 0)
	model.Parent = entry.Placed

	local label = PlotBuilder.EnsureItemLabel(model)
	if label then
		label.Text = labelFor(placed)
		label.TextColor3 = Rarities.Get(placed.Item.Rarity).Color
	end

	local anchor = model.PrimaryPart
	local store = Instance.new("ProximityPrompt")
	store.Name = "StorePrompt"
	store.ActionText = "Store"
	store.ObjectText = itemName(placed.Item) .. (placed.Type == "Egg" and " Egg" or "")
	store.KeyboardKeyCode = Enum.KeyCode.E
	store.GamepadKeyCode = Enum.KeyCode.ButtonX
	store.RequiresLineOfSight = false
	store.MaxActivationDistance = 5
	store.Parent = anchor
	store.Triggered:Connect(function(player)
		PlotService.Store(player, id, entry)
	end)

	local price = placed.Type == "Egg" and Formulas.EggSellPrice(placed.Item) or Formulas.MobSellPrice(placed.Item)
	local sell = Instance.new("ProximityPrompt")
	sell.Name = "SellPrompt"
	sell.ActionText = "Sell"
	sell.ObjectText = "$" .. Format.Number(price)
	sell.KeyboardKeyCode = Enum.KeyCode.F
	sell.GamepadKeyCode = Enum.KeyCode.ButtonY
	sell.RequiresLineOfSight = false
	sell.MaxActivationDistance = 5
	sell.UIOffset = Vector2.new(0, 60)
	sell.Parent = anchor
	sell.Triggered:Connect(function(player)
		PlotService.Sell(player, id, entry)
	end)

	entry.Models[id] = model
	entry.Labels[id] = label
end

local function updateSign(entry, data)
	local used, total = countItems(data), capacity(data)
	PlotBuilder.SetSignText(entry.Model, entry.Owner.DisplayName .. "'s Base\n" .. used .. " / " .. total)

	local maxLevel = Formulas.MaxBaseLevel()
	if data.BaseLevel >= maxLevel then
		PlotBuilder.SetUpgradeText(entry.Model, "Base fully upgraded")
	else
		local cost = Formulas.BaseUpgradeCost(data.BaseLevel)
		PlotBuilder.SetUpgradeText(entry.Model, "Upgrade Base\n$" .. Format.Number(cost)
			.. "  (+" .. GameConfig.Base.SlotsPerLevel .. " slots)")
	end
	if entry.UpgradePrompt then
		entry.UpgradePrompt.Enabled = data.BaseLevel < maxLevel
		entry.UpgradePrompt.ObjectText = data.BaseLevel < maxLevel
			and ("$" .. Format.Number(Formulas.BaseUpgradeCost(data.BaseLevel)))
			or "Max level"
	end
end

local function renderPlot(entry)
	local data = entry.Owner and DataService.Get(entry.Owner)
	for id in pairs(entry.Models) do
		clearItemVisual(entry, id)
	end
	if not data then
		return
	end
	for id, placed in pairs(data.Plot.Items) do
		renderItem(entry, id, placed)
	end
	PlotBuilder.UpdateFence(entry.Model, data.BaseLevel)
	updateSign(entry, data)
end

PlotService.RefreshPlot = function(player)
	local entry = byPlayer[player]
	if entry then
		renderPlot(entry)
	end
end

---------------------------------------------------------------------
-- Поставить предмет
---------------------------------------------------------------------

-- Свободно ли место: рядом не должно быть другого предмета
local function isSpotFree(data, x, z)
	local minDistance = GameConfig.Plot.PlaceMinDistance
	for _, placed in pairs(data.Plot.Items) do
		local dx, dz = (placed.X or 0) - x, (placed.Z or 0) - z
		if dx * dx + dz * dz < minDistance * minDistance then
			return false
		end
	end
	return true
end

-- Игрок нажал кнопку "поставить". Позицию берём с сервера, клиенту не верим.
function PlotService.PlaceFromBackpack(player)
	local entry = byPlayer[player]
	local data = DataService.Get(player)
	if not entry or not data then
		return
	end

	local now = os.clock()
	if now - (lastPlaceAt[player] or 0) < GameConfig.Plot.PlaceCooldown then
		return
	end
	lastPlaceAt[player] = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	if countItems(data) >= capacity(data) then
		Remotes.Notify(player, "Base is full", "Upgrade your base for more space.")
		return
	end

	local x, z = PlotBuilder.ToLocal(entry.Floor, root.Position)
	if not PlotBuilder.IsInside(entry.Floor, x, z) then
		Remotes.Notify(player, "Not your base", "Stand inside your own fence to place eggs.")
		return
	end
	if not isSpotFree(data, x, z) then
		Remotes.Notify(player, "Too close", "There is something here already.")
		return
	end

	-- Пока нет интерфейса выбора: берём самое старое яйцо, а если яиц нет — моба
	local kind, item = "Egg", nil
	local eggId = InventoryService.OldestEggId(player)
	if eggId then
		item = InventoryService.TakeEgg(player, eggId)
	else
		local mobId = InventoryService.OldestMobId(player)
		if mobId then
			kind = "Mob"
			item = InventoryService.TakeMob(player, mobId)
		end
	end
	if not item then
		Remotes.Notify(player, "Backpack empty", "Steal an egg from a biome first.")
		return
	end

	-- Модель смотрит туда же, куда смотрел игрок
	local look = entry.Floor.CFrame:VectorToObjectSpace(root.CFrame.LookVector)
	local yaw = math.atan2(-look.X, -look.Z)

	local placed = { Type = kind, Item = item, X = x, Z = z, R = yaw }
	if kind == "Egg" then
		local seconds = item.HatchLeft or Formulas.HatchTime(item, hatchMultiplier(player))
		item.HatchLeft = nil
		placed.HatchEndsAt = os.time() + math.max(1, math.floor(seconds))
		Remotes.Notify(player, "Egg placed", itemName(item) .. " Egg — " .. Format.Time(seconds))
	end

	local id = InventoryService.NextId(player)
	data.Plot.Items[id] = placed
	renderItem(entry, id, placed)
	updateSign(entry, data)
	recalcIncome(player)
end

---------------------------------------------------------------------
-- Убрать и продать
---------------------------------------------------------------------

-- atEntry — участок, у которого нажали подсказку. Чужой участок трогать нельзя.
function PlotService.Store(player, id, atEntry)
	local entry = byPlayer[player]
	local data = DataService.Get(player)
	if not entry or not data then
		return
	end
	if atEntry and atEntry ~= entry then
		Remotes.Notify(player, "Not your base", "This base belongs to someone else.")
		return
	end
	local placed = data.Plot.Items[id]
	if not placed then
		return
	end

	if placed.Type == "Egg" then
		if not InventoryService.HasEggSpace(player) then
			return
		end
		-- Яйцо в рюкзаке не растёт: запоминаем, сколько осталось до вылупления
		placed.Item.HatchLeft = math.max(0, (placed.HatchEndsAt or 0) - os.time())
		if not InventoryService.AddEggItem(player, placed.Item) then
			return
		end
	else
		if not InventoryService.HasMobSpace(player) then
			return
		end
		if not InventoryService.AddMobItem(player, placed.Item) then
			return
		end
	end

	data.Plot.Items[id] = nil
	clearItemVisual(entry, id)
	updateSign(entry, data)
	recalcIncome(player)
end

function PlotService.Sell(player, id, atEntry)
	local entry = byPlayer[player]
	local data = DataService.Get(player)
	if not entry or not data then
		return
	end
	if atEntry and atEntry ~= entry then
		Remotes.Notify(player, "Not your base", "This base belongs to someone else.")
		return
	end
	local placed = data.Plot.Items[id]
	if not placed then
		return
	end
	local price = placed.Type == "Egg" and Formulas.EggSellPrice(placed.Item) or Formulas.MobSellPrice(placed.Item)
	data.Plot.Items[id] = nil
	clearItemVisual(entry, id)
	EconomyService.AddMoney(player, price)
	Remotes.Notify(player, "Sold", InventoryService.Describe(placed.Item) .. " for $" .. Format.Number(price))
	updateSign(entry, data)
	recalcIncome(player)
end

---------------------------------------------------------------------
-- Улучшение участка
---------------------------------------------------------------------

function PlotService.Upgrade(player)
	local entry = byPlayer[player]
	local data = DataService.Get(player)
	if not entry or not data then
		return
	end
	if data.BaseLevel >= Formulas.MaxBaseLevel() then
		Remotes.Notify(player, "Max base", "Your base is fully upgraded.")
		return
	end
	local cost = Formulas.BaseUpgradeCost(data.BaseLevel)
	if not EconomyService.TrySpend(player, cost) then
		Remotes.Notify(player, "Not enough money", "You need $" .. Format.Number(cost))
		return
	end
	data.BaseLevel = data.BaseLevel + 1
	player:SetAttribute("Slots", capacity(data))
	PlotBuilder.UpdateFence(entry.Model, data.BaseLevel)
	updateSign(entry, data)
	Remotes.Notify(player, "Base upgraded", "Now " .. capacity(data) .. " slots.")
end

---------------------------------------------------------------------
-- Вылупление
---------------------------------------------------------------------

local function hatch(data, id, placed)
	local item = placed.Item
	item.HatchLeft = nil
	item.Mutation = Formulas.RollMutation(rng)
	placed.Type = "Mob"
	placed.HatchEndsAt = nil
	data.Index[item.MobId] = true -- индекс мобов (этап 7)
	return item
end

-- Проверяет все яйца игрока. Возвращает true, если хоть одно вылупилось.
local function processHatching(player, data, notify)
	local now = os.time()
	local hatched = false
	for id, placed in pairs(data.Plot.Items) do
		if placed.Type == "Egg" and now >= (placed.HatchEndsAt or 0) then
			local item = hatch(data, id, placed)
			hatched = true
			if notify then
				Remotes.Notify(player, "Egg hatched!", InventoryService.Describe(item))
				-- Редкая мутация — событие для всего сервера
				local mutation = Mutations.Get(item.Mutation)
				if mutation.Announce then
					Remotes.NotifyAll(
						mutation.DisplayName .. " hatch!",
						player.DisplayName .. " got a " .. InventoryService.Describe(item)
					)
				end
			end
		end
	end
	return hatched
end

-- Мгновенное вылупление (Developer Product на этапе 10 и тестовая команда)
function PlotService.HatchNow(player, id)
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local placed = data.Plot.Items[tostring(id)]
	if not placed or placed.Type ~= "Egg" then
		return false
	end
	placed.HatchEndsAt = os.time()
	processHatching(player, data, true)
	PlotService.RefreshPlot(player)
	recalcIncome(player)
	return true
end

---------------------------------------------------------------------
-- Выдача и освобождение участка
---------------------------------------------------------------------

local function teleportToPlot(player, entry, character)
	local cframe = PlotBuilder.GetSpawnCFrame(entry.Model)
	if not cframe then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if root and character.Parent then
		character:PivotTo(cframe)
		SpeedService.MarkTeleport(player) -- это честный телепорт, не нарушение
	end
end

-- Отправить игрока на свой участок (сброс раунда, появление персонажа)
function PlotService.SendHome(player)
	local entry = byPlayer[player]
	local character = player.Character
	if entry and character then
		teleportToPlot(player, entry, character)
	end
end

local function claimPlot(player, data)
	local entry
	for _, candidate in ipairs(plots) do
		if not candidate.Owner then
			entry = candidate
			break
		end
	end
	if not entry then
		warn("[PlotService] Не хватило участков для игрока " .. player.Name)
		Remotes.Notify(player, "No free base", "The server is full of bases.")
		return nil
	end

	entry.Owner = player
	byPlayer[player] = entry
	player:SetAttribute("PlotName", entry.Model.Name)
	player:SetAttribute("Slots", capacity(data))
	SpeedService.SetTreadmill(player, PlotBuilder.GetTreadmillSurface(entry.Model))
	PlotBuilder.SetTreadmillText(entry.Model, SpeedService.GetTreadmillText(player))
	renderPlot(entry)

	entry.CharacterConnection = player.CharacterAdded:Connect(function(character)
		task.defer(teleportToPlot, player, entry, character)
	end)
	if player.Character then
		task.defer(teleportToPlot, player, entry, player.Character)
	end
	return entry
end

local function releasePlot(player)
	local entry = byPlayer[player]
	lastPlaceAt[player] = nil
	if not entry then
		return
	end
	if entry.CharacterConnection then
		entry.CharacterConnection:Disconnect()
		entry.CharacterConnection = nil
	end
	for id in pairs(entry.Models) do
		clearItemVisual(entry, id)
	end
	entry.Owner = nil
	byPlayer[player] = nil
	SpeedService.SetTreadmill(player, nil)
	PlotBuilder.SetTreadmillText(entry.Model, "")
	PlotBuilder.UpdateFence(entry.Model, 0)
	PlotBuilder.SetSignText(entry.Model, "Empty Base")
	PlotBuilder.SetUpgradeText(entry.Model, "")
	if entry.UpgradePrompt then
		entry.UpgradePrompt.Enabled = false
	end
end

---------------------------------------------------------------------
-- Загрузка игрока
---------------------------------------------------------------------

local function onProfileLoaded(player, data)
	migrateOldSlots(data)

	-- 1. Офлайн-доход считаем ДО вылупления: платим только за тех мобов,
	--    которые уже стояли на участке, когда игрок вышел.
	EconomyService.ApplyOfflineIncome(player, EconomyService.CalculateBaseIncome(data))

	-- 2. Яйца, у которых срок вышел, пока игрока не было
	processHatching(player, data, false)

	-- Проверка геймпассов ходит в интернет, поэтому игрок мог успеть выйти
	if not player.Parent then
		return
	end

	-- 3. Участок и доход
	claimPlot(player, data)
	recalcIncome(player)

	-- Заранее узнаём про геймпасс x2 вылупление, чтобы потом не ждать ответа Roblox
	task.spawn(PassService.Has, player, "X2Hatch")
end

-- Купил геймпасс x2 вылупление — ускоряем яйца, которые уже стоят на участке
local function onHatchPassGranted(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local now = os.time()
	for _, placed in pairs(data.Plot.Items) do
		if placed.Type == "Egg" then
			local left = math.max(0, (placed.HatchEndsAt or 0) - now)
			placed.HatchEndsAt = now + math.floor(left / 2)
		end
	end
	PlotService.RefreshPlot(player)
end

---------------------------------------------------------------------
-- Главный цикл: вылупление, доход, таймеры
---------------------------------------------------------------------

local function tick(deltaTime)
	for player, entry in pairs(byPlayer) do
		local data = DataService.Get(player)
		if data then
			if processHatching(player, data, true) then
				renderPlot(entry)
				recalcIncome(player)
			end

			local income = EconomyService.GetIncomePerSecond(player)
			if income > 0 then
				EconomyService.AddMoney(player, income * deltaTime)
			end

			PlotBuilder.SetTreadmillText(entry.Model, SpeedService.GetTreadmillText(player))

			-- Обновляем только таймеры яиц, остальные подписи меняются при действиях
			for id, placed in pairs(data.Plot.Items) do
				if placed.Type == "Egg" then
					local label = entry.Labels[id]
					if label then
						label.Text = labelFor(placed)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Запуск
---------------------------------------------------------------------

local function setupUpgradePrompt(entry)
	local part = PlotBuilder.GetUpgradePart(entry.Model)
	if not part then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UpgradePrompt"
	prompt.ActionText = "Upgrade Base"
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 8
	prompt.Enabled = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		if byPlayer[player] == entry then
			PlotService.Upgrade(player)
		else
			Remotes.Notify(player, "Not your base", "This base belongs to someone else.")
		end
	end)
	entry.UpgradePrompt = prompt
end

local function setupTreadmillPrompt(entry)
	local part = PlotBuilder.GetTreadmill(entry.Model)
	if not part then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TreadmillPrompt"
	prompt.ActionText = "Upgrade Treadmill"
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 8
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		if byPlayer[player] ~= entry then
			Remotes.Notify(player, "Not your base", "This treadmill belongs to someone else.")
			return
		end
		if SpeedService.UpgradeTreadmill(player) then
			PlotBuilder.SetTreadmillText(entry.Model, SpeedService.GetTreadmillText(player))
		end
	end)
end

function PlotService.Init()
	local folder = PlotBuilder.EnsurePlots()
	for _, model in ipairs(PlotBuilder.GetPlots(folder)) do
		local floor = PlotBuilder.GetFloor(model)
		if not floor then
			warn("[PlotService] В участке " .. model.Name .. " нет детали Floor — пропускаем")
		else
			-- Подсказка автору: что из необязательных деталей не найдено внутри участка
			local missing = {}
			for _, name in ipairs({ "Spawn", "Sign", "Upgrade", "Treadmill" }) do
				if not model:FindFirstChild(name, true) then
					table.insert(missing, name)
				end
			end
			if #missing > 0 then
				warn("[PlotService] В участке " .. model.Name .. " не найдены детали: "
					.. table.concat(missing, ", ")
					.. ". Проверь, что они лежат ВНУТРИ модели участка и названы точно так.")
			end

			local entry = {
				Model = model,
				Floor = floor,
				Placed = PlotBuilder.EnsurePlacedFolder(model),
				Owner = nil,
				Models = {},
				Labels = {},
			}
			setupUpgradePrompt(entry)
			setupTreadmillPrompt(entry)
			PlotBuilder.UpdateFence(model, 0)
			PlotBuilder.SetSignText(model, "Empty Base")
			table.insert(plots, entry)
		end
	end
	print("[PlotService] Участков готово: " .. #plots)

	Remotes.Event("PlaceItem").OnServerEvent:Connect(function(player)
		PlotService.PlaceFromBackpack(player)
	end)

	DataService.ProfileLoaded:Connect(onProfileLoaded)
	Players.PlayerRemoving:Connect(releasePlot)

	PassService.PassGranted:Connect(function(player, passName)
		if passName == "X2Hatch" then
			onHatchPassGranted(player)
		elseif passName == "X2Money" then
			EconomyService.RefreshMoneyMultiplier(player)
			recalcIncome(player)
		end
	end)

	task.spawn(function()
		while true do
			local deltaTime = task.wait(GameConfig.Plot.TickInterval)
			local ok, err = pcall(tick, deltaTime)
			if not ok then
				warn("[PlotService] Ошибка в цикле дохода: " .. tostring(err))
			end
		end
	end)
end

return PlotService
