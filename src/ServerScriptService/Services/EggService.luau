-- EggService: яйца в биомах.
--
--  * спавнит яйца в биомах (общие для всех игроков сервера);
--  * даёт поднять яйцо: оно висит над головой и замедляет игрока;
--  * засчитывает кражу, когда игрок донёс яйцо в safe zone;
--  * при появлении редкого яйца объявляет об этом всему серверу.
--
-- Носить можно только одно яйцо. Вес яйца кладётся в атрибут CarryWeight,
-- а SpeedService сам пересчитывает скорость.
--
-- События для следующих этапов:
--   EggService.EggTaken      (player, biomeId, item)  -- босс просыпается (этап 5)
--   EggService.EggDelivered  (player, item)
--   EggService.EggDropped    (player, biomeId, item)  -- удар мечом (этап 6)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local WorldService = require(script.Parent.WorldService)
local PlotBuilder = require(script.Parent.PlotBuilder)

local EggService = {}

local rng = Random.new()
local E = GameConfig.Egg

local eggsFolder          -- Workspace.WorldEggs
local activeEggs = {}     -- [eggId] = { Id, BiomeId, Item, Model, Position, Carrier }
local carrying = {}       -- [player] = запись яйца
local nextEggId = 1

local takenEvent = Instance.new("BindableEvent")
EggService.EggTaken = takenEvent.Event

local deliveredEvent = Instance.new("BindableEvent")
EggService.EggDelivered = deliveredEvent.Event

local droppedEvent = Instance.new("BindableEvent")
EggService.EggDropped = droppedEvent.Event

---------------------------------------------------------------------
-- Вспомогательное
---------------------------------------------------------------------

local function itemName(item)
	local mob = Mobs[item.MobId]
	return mob and mob.DisplayName or item.MobId
end

local function describeEgg(item)
	return Rarities.Get(item.Rarity).DisplayName .. " " .. itemName(item)
		.. " Egg (" .. Format.Weight(item.Weight) .. ")"
end

-- Скрепляет все детали модели с главной, чтобы её можно было носить
local function weldModel(model)
	local primary = model.PrimaryPart
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
			if descendant ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = descendant
				weld.Parent = primary
			end
		end
	end
end

local function anchorModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
end

---------------------------------------------------------------------
-- Спавн
---------------------------------------------------------------------

local function makePrompt(egg)
	local anchor = egg.Model.PrimaryPart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TakePrompt"
	prompt.ActionText = "Take"
	prompt.ObjectText = describeEgg(egg.Item)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = E.PickupDistance
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		EggService.Take(player, egg.Id)
	end)
	egg.Prompt = prompt
end

local function spawnEgg(biome, taken)
	local item = Formulas.RollEgg(rng, biome.Id)
	if not item then
		return nil
	end
	local position = WorldService.FindEggSpawn(biome, taken, eggsFolder)
	if not position then
		warn("[EggService] В биоме " .. biome.Id .. " не нашлось места для яйца")
		return nil
	end

	local model = PlotBuilder.MakeItemModel(item, "Egg")
	if not model then
		return nil
	end
	PlotBuilder.PlaceOnGround(model, position, math.random() * math.pi * 2)
	anchorModel(model)

	local id = tostring(nextEggId)
	nextEggId = nextEggId + 1
	model.Name = "Egg_" .. id
	model.Parent = eggsFolder

	local egg = {
		Id = id,
		BiomeId = biome.Id,
		Item = item,
		Model = model,
		Position = position,
	}
	activeEggs[id] = egg
	makePrompt(egg)

	-- Редкое яйцо — новость для всего сервера
	if Rarities.Get(item.Rarity).Announce then
		Remotes.NotifyAll(Rarities.Get(item.Rarity).DisplayName .. " egg!",
			describeEgg(item) .. " spawned in " .. (biome.Config.DisplayName or biome.Id))
	end
	return egg
end

-- Заново расставляет яйца во всех биомах (вызывает RoundService)
function EggService.SpawnRound()
	for _, biome in ipairs(WorldService.GetBiomes()) do
		local taken = {}
		local count = biome.Config.EggsAtOnce or 1
		for _ = 1, count do
			local egg = spawnEgg(biome, taken)
			if egg then
				table.insert(taken, egg.Position)
			end
		end
	end
end

---------------------------------------------------------------------
-- Поднять яйцо
---------------------------------------------------------------------

local function detach(player, egg)
	carrying[player] = nil
	egg.Carrier = nil
	player:SetAttribute("CarryWeight", 0)
	player:SetAttribute("CarryRarity", "")
end

function EggService.GetCarried(player)
	return carrying[player]
end

function EggService.Take(player, eggId)
	local egg = activeEggs[eggId]
	if not egg or egg.Carrier then
		return false
	end
	if carrying[player] then
		Remotes.Notify(player, "Hands full", "You already carry an egg.")
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	-- Сервер сам проверяет расстояние, клиенту не верим
	if (root.Position - egg.Model:GetPivot().Position).Magnitude > E.PickupDistance * 1.5 then
		return false
	end

	egg.Carrier = player
	carrying[player] = egg
	if egg.Prompt then
		egg.Prompt.Enabled = false
	end

	weldModel(egg.Model)
	-- Центр яйца должен оказаться над головой, а не его PrimaryPart
	PlotBuilder.CenterAt(egg.Model, (root.CFrame * CFrame.new(0, E.CarryHeight, 0)).Position)
	local primary = egg.Model.PrimaryPart
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = primary
	-- Держим ту позицию, в которую только что поставили модель
	weld.C0 = root.CFrame:ToObjectSpace(primary.CFrame)
	weld.Parent = primary
	egg.Model.Parent = character

	-- Тяжёлое яйцо замедляет: SpeedService читает этот атрибут
	player:SetAttribute("CarryWeight", egg.Item.Weight)
	player:SetAttribute("CarryRarity", egg.Item.Rarity)

	Remotes.Notify(player, "Egg taken", describeEgg(egg.Item) .. " — run to the safe zone!")
	takenEvent:Fire(player, egg.BiomeId, egg.Item)
	return true
end

---------------------------------------------------------------------
-- Положить яйцо обратно на землю
---------------------------------------------------------------------

-- Яйцо выпадает из рук (удар мечом на этапе 6, поимка боссом на этапе 5)
function EggService.Drop(player, position)
	local egg = carrying[player]
	if not egg then
		return false
	end
	local model = egg.Model
	if not model or not model.Parent or not model.PrimaryPart then
		-- Модель уже уничтожена (например, вместе с персонажем)
		detach(player, egg)
		activeEggs[egg.Id] = nil
		return false
	end
	local weld = model.PrimaryPart:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	detach(player, egg)

	local ground = position or model:GetPivot().Position
	model.Parent = eggsFolder
	PlotBuilder.PlaceOnGround(model, ground, 0)
	anchorModel(model)
	egg.Position = ground
	if egg.Prompt then
		egg.Prompt.Enabled = true
	end
	droppedEvent:Fire(player, egg.BiomeId, egg.Item)
	return true
end

---------------------------------------------------------------------
-- Донёс до safe zone
---------------------------------------------------------------------

local function deliver(player, egg)
	local data = DataService.Get(player)
	if not data then
		return
	end
	if not InventoryService.HasEggSpace(player) then
		if os.clock() - (egg.WarnedAt or 0) > 5 then
			egg.WarnedAt = os.clock()
			Remotes.Notify(player, "Backpack full", "Sell some eggs first.")
		end
		return
	end

	local item = egg.Item
	detach(player, egg)
	activeEggs[egg.Id] = nil
	egg.Model:Destroy()

	InventoryService.AddEggItem(player, item)
	data.Stats.EggsStolen = data.Stats.EggsStolen + 1
	Remotes.Notify(player, "Egg secured!", describeEgg(item))
	deliveredEvent:Fire(player, item)
end

---------------------------------------------------------------------
-- Очистка между раундами
---------------------------------------------------------------------

-- Удаляет все яйца в мире и в руках (кроме тех, что уже в рюкзаке)
function EggService.ClearAll()
	for player, egg in pairs(carrying) do
		detach(player, egg)
		Remotes.Notify(player, "Egg lost", "You did not reach the safe zone in time.")
		egg.Model:Destroy()
	end
	carrying = {}
	for id, egg in pairs(activeEggs) do
		if egg.Model then
			egg.Model:Destroy()
		end
		activeEggs[id] = nil
	end
end

---------------------------------------------------------------------
-- Цикл: доставка и потерянные яйца
---------------------------------------------------------------------

local function tick()
	for player, egg in pairs(carrying) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			-- Игрок умер: яйцо падает на землю там, где он стоял
			EggService.Drop(player, root and root.Position or nil)
		elseif WorldService.IsInSafeZone(root.Position) then
			deliver(player, egg)
		end
	end
end

-- Список яиц в мире (для тестовых команд и этапа 5)
function EggService.GetActive()
	local list = {}
	for _, egg in pairs(activeEggs) do
		table.insert(list, egg)
	end
	return list
end

function EggService.Init()
	eggsFolder = workspace:FindFirstChild("WorldEggs")
	if not eggsFolder then
		eggsFolder = Instance.new("Folder")
		eggsFolder.Name = "WorldEggs"
		eggsFolder.Parent = workspace
	end

	local function watchCharacter(player)
		player.CharacterRemoving:Connect(function(character)
			if carrying[player] then
				local root = character:FindFirstChild("HumanoidRootPart")
				EggService.Drop(player, root and root.Position or nil)
			end
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in ipairs(Players:GetPlayers()) do
		watchCharacter(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local egg = carrying[player]
		if egg then
			detach(player, egg)
			if egg.Model then
				egg.Model:Destroy()
			end
			activeEggs[egg.Id] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(E.CheckInterval)
			local ok, err = pcall(tick)
			if not ok then
				warn("[EggService] Ошибка в цикле яиц: " .. tostring(err))
			end
		end
	end)
end

return EggService
