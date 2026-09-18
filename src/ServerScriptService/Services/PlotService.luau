-- PlotService: участки игроков.
--
-- Что делает:
--  * выдаёт свободный участок при входе и освобождает при выходе;
--  * показывает яйца и мобов на слотах;
--  * вылупляет яйца (в том числе пока игрок был офлайн — время хранится как дата конца);
--  * считает доход в секунду и начисляет деньги;
--  * позволяет убрать предмет в рюкзак, продать его и открыть новый слот за деньги.
--
-- Управление пока через ProximityPrompt на слоте (настоящий интерфейс — этап 11):
--   E — поставить яйцо из рюкзака / убрать предмет в рюкзак / открыть слот
--   F — продать предмет со слота

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
local PlotBuilder = require(script.Parent.PlotBuilder)

local PlotService = {}

local rng = Random.new()

local plots = {}    -- список участков: { Model, SlotParts, Owner, Prompts, Labels, Original }
local byPlayer = {} -- [player] = участок

local LOCKED_COLOR = Color3.fromRGB(60, 60, 65)

---------------------------------------------------------------------
-- Мелкие помощники
---------------------------------------------------------------------

local function slotKey(index)
	return tostring(index)
end

local function getSlot(data, index)
	return data.Plot.Slots[slotKey(index)]
end

local function setSlot(data, index, value)
	data.Plot.Slots[slotKey(index)] = value
end

local function hatchMultiplier(player)
	return PassService.Has(player, "X2Hatch") and 2 or 1
end

local function itemName(item)
	local mob = Mobs[item.MobId]
	return mob and mob.DisplayName or item.MobId
end

---------------------------------------------------------------------
-- Доход
---------------------------------------------------------------------

-- Пересчитывает доход в секунду и показывает его игроку
local function recalcIncome(player)
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local base = EconomyService.CalculateBaseIncome(data)
	local income = base * EconomyService.GetMoneyMultiplier(player)
	EconomyService.SetIncomePerSecond(player, income)
	return income
end

PlotService.RecalcIncome = recalcIncome

---------------------------------------------------------------------
-- Показ слота
---------------------------------------------------------------------

local function labelForSlot(data, index, slot, unlockedSlots)
	if index > unlockedSlots then
		if index == unlockedSlots + 1 and unlockedSlots < GameConfig.Base.MaxSlots then
			return "Unlock: $" .. Format.Number(Formulas.BaseUpgradeCost(data.BaseLevel))
		end
		return "Locked"
	end
	if not slot then
		return "Empty"
	end
	if slot.Type == "Egg" then
		local left = math.max(0, (slot.HatchEndsAt or 0) - os.time())
		return Rarities.Get(slot.Item.Rarity).DisplayName .. " " .. itemName(slot.Item) .. " Egg\n" .. Format.Time(left)
	end
	return InventoryService.Describe(slot.Item) .. "\n$" .. Format.Number(Formulas.MobIncome(slot.Item)) .. "/s"
end

-- Перерисовывает один слот: модель, подписи и подсказки
local function refreshSlot(entry, index)
	local slotPart = entry.SlotParts[index]
	if not slotPart then
		return
	end
	local player = entry.Owner
	local data = player and DataService.Get(player)
	local label = entry.Labels[index]
	local mainPrompt = entry.Prompts[index] and entry.Prompts[index].Main
	local sellPrompt = entry.Prompts[index] and entry.Prompts[index].Sell

	if not data then
		PlotBuilder.ClearSlot(slotPart)
		if label then
			label.Text = ""
		end
		return
	end

	local unlockedSlots = Formulas.BaseSlots(data.BaseLevel)
	local slot = getSlot(data, index)
	local locked = index > unlockedSlots

	-- Закрытые слоты выглядят тёмными
	local original = entry.Original[slotPart]
	if original then
		slotPart.Color = locked and LOCKED_COLOR or original.Color
		slotPart.Transparency = locked and 0.5 or original.Transparency
	end

	-- Модель на слоте
	if locked or not slot then
		PlotBuilder.ClearSlot(slotPart)
	else
		local current = slotPart:FindFirstChild("Display")
		local signature = slot.Type .. "|" .. slot.Item.MobId .. "|" .. tostring(slot.Item.Weight) .. "|" .. tostring(slot.Item.Mutation)
		if not current or current:GetAttribute("Signature") ~= signature then
			local model = PlotBuilder.MakeItemModel(slot.Item, slot.Type)
			if model then
				model:SetAttribute("Signature", signature)
				PlotBuilder.ShowOnSlot(slotPart, model)
			end
		end
	end

	-- Подпись
	if label then
		label.Text = labelForSlot(data, index, slot, unlockedSlots)
		label.TextColor3 = slot and Rarities.Get(slot.Item.Rarity).Color or Color3.fromRGB(255, 255, 255)
	end

	-- Подсказки
	if mainPrompt then
		if locked then
			local isNext = index == unlockedSlots + 1 and unlockedSlots < GameConfig.Base.MaxSlots
			mainPrompt.Enabled = isNext
			mainPrompt.ActionText = "Unlock"
			mainPrompt.ObjectText = isNext and ("$" .. Format.Number(Formulas.BaseUpgradeCost(data.BaseLevel))) or "Locked"
		elseif slot then
			mainPrompt.Enabled = true
			mainPrompt.ActionText = "Store"
			mainPrompt.ObjectText = itemName(slot.Item) .. (slot.Type == "Egg" and " Egg" or "")
		else
			mainPrompt.Enabled = true
			mainPrompt.ActionText = "Place"
			mainPrompt.ObjectText = "Empty slot"
		end
	end

	if sellPrompt then
		if slot and not locked then
			local price = slot.Type == "Egg" and Formulas.EggSellPrice(slot.Item) or Formulas.MobSellPrice(slot.Item)
			sellPrompt.Enabled = true
			sellPrompt.ActionText = "Sell"
			sellPrompt.ObjectText = "$" .. Format.Number(price)
		else
			sellPrompt.Enabled = false
		end
	end
end

local function refreshAllSlots(entry)
	for index in pairs(entry.SlotParts) do
		refreshSlot(entry, index)
	end
end

PlotService.RefreshPlot = function(player)
	local entry = byPlayer[player]
	if entry then
		refreshAllSlots(entry)
	end
end

---------------------------------------------------------------------
-- Действия игрока
---------------------------------------------------------------------

-- Ставит предмет из рюкзака в пустой слот.
-- Пока нет интерфейса выбора — берём самое старое яйцо, а если яиц нет, то моба.
local function placeFromBackpack(player, entry, data, index)
	local eggId = InventoryService.OldestEggId(player)
	if eggId then
		local item = InventoryService.TakeEgg(player, eggId)
		if not item then
			return
		end
		-- Если яйцо уже лежало в слоте и его убрали, оно продолжает с того же места
		local seconds = item.HatchLeft or Formulas.HatchTime(item, hatchMultiplier(player))
		item.HatchLeft = nil
		setSlot(data, index, {
			Type = "Egg",
			Item = item,
			HatchEndsAt = os.time() + math.max(1, math.floor(seconds)),
		})
		Remotes.Notify(player, "Egg placed", itemName(item) .. " Egg — " .. Format.Time(seconds))
		refreshSlot(entry, index)
		return
	end

	local mobId = InventoryService.OldestMobId(player)
	if mobId then
		local item = InventoryService.TakeMob(player, mobId)
		if not item then
			return
		end
		setSlot(data, index, { Type = "Mob", Item = item })
		refreshSlot(entry, index)
		recalcIncome(player)
		return
	end

	Remotes.Notify(player, "Backpack empty", "Steal an egg from a biome first.")
end

-- Убирает предмет со слота обратно в рюкзак
local function storeToBackpack(player, entry, data, index, slot)
	if slot.Type == "Egg" then
		if not InventoryService.HasEggSpace(player) then
			return
		end
		-- Яйцо в рюкзаке не растёт: запоминаем, сколько осталось до вылупления
		local item = slot.Item
		item.HatchLeft = math.max(0, (slot.HatchEndsAt or 0) - os.time())
		if not InventoryService.AddEggItem(player, item) then
			return
		end
	else
		if not InventoryService.HasMobSpace(player) then
			return
		end
		if not InventoryService.AddMobItem(player, slot.Item) then
			return
		end
	end
	setSlot(data, index, nil)
	refreshSlot(entry, index)
	recalcIncome(player)
end

local function unlockSlot(player, entry, data)
	local unlockedSlots = Formulas.BaseSlots(data.BaseLevel)
	if unlockedSlots >= GameConfig.Base.MaxSlots then
		Remotes.Notify(player, "Max base", "All slots are unlocked.")
		return
	end
	local cost = Formulas.BaseUpgradeCost(data.BaseLevel)
	if not EconomyService.TrySpend(player, cost) then
		Remotes.Notify(player, "Not enough money", "You need $" .. Format.Number(cost))
		return
	end
	data.BaseLevel = data.BaseLevel + 1
	player:SetAttribute("Slots", Formulas.BaseSlots(data.BaseLevel))
	Remotes.Notify(player, "Slot unlocked", "Now " .. Formulas.BaseSlots(data.BaseLevel) .. " slots.")
	refreshAllSlots(entry)
end

local function onMainPrompt(player, entry, index)
	if entry.Owner ~= player then
		Remotes.Notify(player, "Not your plot", "This base belongs to someone else.")
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	local unlockedSlots = Formulas.BaseSlots(data.BaseLevel)
	if index > unlockedSlots then
		if index == unlockedSlots + 1 then
			unlockSlot(player, entry, data)
		end
		return
	end
	local slot = getSlot(data, index)
	if slot then
		storeToBackpack(player, entry, data, index, slot)
	else
		placeFromBackpack(player, entry, data, index)
	end
end

local function onSellPrompt(player, entry, index)
	if entry.Owner ~= player then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	if index > Formulas.BaseSlots(data.BaseLevel) then
		return
	end
	local slot = getSlot(data, index)
	if not slot then
		return
	end
	local price = slot.Type == "Egg" and Formulas.EggSellPrice(slot.Item) or Formulas.MobSellPrice(slot.Item)
	setSlot(data, index, nil)
	EconomyService.AddMoney(player, price)
	Remotes.Notify(player, "Sold", InventoryService.Describe(slot.Item) .. " for $" .. Format.Number(price))
	refreshSlot(entry, index)
	recalcIncome(player)
end

---------------------------------------------------------------------
-- Вылупление
---------------------------------------------------------------------

local function hatchSlot(player, data, index, slot)
	local item = slot.Item
	item.HatchLeft = nil
	item.Mutation = Formulas.RollMutation(rng)
	setSlot(data, index, { Type = "Mob", Item = item })
	data.Index[item.MobId] = true -- индекс мобов (этап 7)
	return item
end

-- Проверяет все яйца игрока. Возвращает true, если хоть одно вылупилось.
local function processHatching(player, data, notify)
	local now = os.time()
	local hatched = false
	for key, slot in pairs(data.Plot.Slots) do
		local index = tonumber(key)
		if index and slot.Type == "Egg" and now >= (slot.HatchEndsAt or 0) then
			local item = hatchSlot(player, data, index, slot)
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

-- Мгновенное вылупление (для Developer Product на этапе 10 и тестовой команды)
function PlotService.HatchNow(player, index)
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local slot = getSlot(data, index)
	if not slot or slot.Type ~= "Egg" then
		return false
	end
	slot.HatchEndsAt = os.time()
	local item = hatchSlot(player, data, index, slot)
	Remotes.Notify(player, "Egg hatched!", InventoryService.Describe(item))
	PlotService.RefreshPlot(player)
	recalcIncome(player)
	return true
end

---------------------------------------------------------------------
-- Выдача и освобождение участка
---------------------------------------------------------------------

local function buildPrompts(entry)
	for index, slotPart in pairs(entry.SlotParts) do
		entry.Original[slotPart] = { Color = slotPart.Color, Transparency = slotPart.Transparency }

		local main = Instance.new("ProximityPrompt")
		main.Name = "SlotPrompt"
		main.ActionText = "Place"
		main.ObjectText = "Slot " .. index
		main.KeyboardKeyCode = Enum.KeyCode.E
		main.GamepadKeyCode = Enum.KeyCode.ButtonX
		main.RequiresLineOfSight = false
		main.MaxActivationDistance = 10
		main.Parent = slotPart
		main.Triggered:Connect(function(player)
			onMainPrompt(player, entry, index)
		end)

		local sell = Instance.new("ProximityPrompt")
		sell.Name = "SellPrompt"
		sell.ActionText = "Sell"
		sell.ObjectText = ""
		sell.KeyboardKeyCode = Enum.KeyCode.F
		sell.GamepadKeyCode = Enum.KeyCode.ButtonY
		sell.RequiresLineOfSight = false
		sell.MaxActivationDistance = 10
		sell.Enabled = false
		sell.UIOffset = Vector2.new(0, 60)
		sell.Parent = slotPart
		sell.Triggered:Connect(function(player)
			onSellPrompt(player, entry, index)
		end)

		entry.Prompts[index] = { Main = main, Sell = sell }
		entry.Labels[index] = PlotBuilder.EnsureSlotLabel(slotPart)
	end
end

local function clearPrompts(entry)
	for index, prompts in pairs(entry.Prompts) do
		prompts.Main:Destroy()
		prompts.Sell:Destroy()
		entry.Prompts[index] = nil
	end
	for slotPart, original in pairs(entry.Original) do
		if slotPart.Parent then
			slotPart.Color = original.Color
			slotPart.Transparency = original.Transparency
		end
		entry.Original[slotPart] = nil
	end
	for index, slotPart in pairs(entry.SlotParts) do
		PlotBuilder.ClearSlot(slotPart)
		local label = entry.Labels[index]
		if label then
			label.Text = ""
		end
	end
end

local function teleportToPlot(player, entry, character)
	local cframe = PlotBuilder.GetSpawnCFrame(entry.Model)
	if not cframe then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if root and character.Parent then
		character:PivotTo(cframe)
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
	player:SetAttribute("Slots", Formulas.BaseSlots(data.BaseLevel))
	PlotBuilder.SetSignText(entry.Model, player.DisplayName .. "'s Base")
	buildPrompts(entry)
	refreshAllSlots(entry)

	-- Появление на своём участке
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
	if not entry then
		return
	end
	if entry.CharacterConnection then
		entry.CharacterConnection:Disconnect()
		entry.CharacterConnection = nil
	end
	clearPrompts(entry)
	PlotBuilder.SetSignText(entry.Model, "Empty Base")
	entry.Owner = nil
	byPlayer[player] = nil
end

---------------------------------------------------------------------
-- Загрузка игрока
---------------------------------------------------------------------

local function onProfileLoaded(player, data)
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

-- Купил геймпасс x2 вылупление — ускоряем яйца, которые уже лежат в слотах
local function onHatchPassGranted(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local now = os.time()
	for _, slot in pairs(data.Plot.Slots) do
		if slot.Type == "Egg" then
			local left = math.max(0, (slot.HatchEndsAt or 0) - now)
			slot.HatchEndsAt = now + math.floor(left / 2)
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
				refreshAllSlots(entry)
				recalcIncome(player)
			end

			local income = EconomyService.GetIncomePerSecond(player)
			if income > 0 then
				EconomyService.AddMoney(player, income * deltaTime)
			end

			-- Обновляем только таймеры яиц, остальные подписи меняются при действиях
			local unlockedSlots = Formulas.BaseSlots(data.BaseLevel)
			for index, label in pairs(entry.Labels) do
				local slot = getSlot(data, index)
				if slot and slot.Type == "Egg" and index <= unlockedSlots then
					label.Text = labelForSlot(data, index, slot, unlockedSlots)
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Запуск
---------------------------------------------------------------------

function PlotService.Init()
	local folder = PlotBuilder.EnsurePlots()
	for _, model in ipairs(PlotBuilder.GetPlots(folder)) do
		local slotParts = PlotBuilder.GetSlotParts(model)
		if next(slotParts) == nil then
			warn("[PlotService] В участке " .. model.Name .. " нет деталей Slot1, Slot2, ... — пропускаем")
		else
			table.insert(plots, {
				Model = model,
				SlotParts = slotParts,
				Owner = nil,
				Prompts = {},
				Labels = {},
				Original = {},
			})
			PlotBuilder.SetSignText(model, "Empty Base")
		end
	end
	print("[PlotService] Участков готово: " .. #plots)

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
