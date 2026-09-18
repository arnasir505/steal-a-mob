-- InventoryService: рюкзак игрока — яйца и мобы, которые не стоят на участке.
--
-- Предмет (item) выглядит так:
--   { MobId = "Chicken", Rarity = "Rare", Weight = 1.5, Mutation = "None" }
-- Редкость у каждого яйца своя: Курица бывает и Common, и Rare.
-- У яйца мутации нет — она выпадает при вылуплении.
-- Каждый предмет в рюкзаке лежит под своим номером-строкой: Backpack.Eggs["7"] = item
--
-- Как использовать:
--   local id = InventoryService.AddEgg(player, "Chicken", "Rare", 2.5)
--   local item = InventoryService.TakeEgg(player, id)     -- вынуть (например, чтобы поставить в слот)
--   InventoryService.SellMob(player, id)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local InventoryService = {}

local changedEvent = Instance.new("BindableEvent")
InventoryService.Changed = changedEvent.Event -- (player) — рюкзак изменился

---------------------------------------------------------------------
-- Вспомогательное
---------------------------------------------------------------------

local function countKeys(tbl)
	local n = 0
	for _ in pairs(tbl) do
		n = n + 1
	end
	return n
end

local function nextItemId(data)
	local id = data.NextItemId or 1
	data.NextItemId = id + 1
	return tostring(id)
end

-- Собирает корректный предмет или возвращает nil, если данные мусорные
function InventoryService.MakeItem(mobId, rarity, weight, mutation)
	if not Mobs[mobId] then
		return nil
	end
	if type(weight) ~= "number" or weight ~= weight then
		return nil
	end
	if not Rarities.Data[rarity] then
		rarity = Rarities.Order[1]
	end
	if mutation == nil or not Mutations.Data[mutation] then
		mutation = "None"
	end
	return {
		MobId = mobId,
		Rarity = rarity,
		Weight = Formulas.ClampWeight(weight),
		Mutation = mutation,
	}
end

-- Имя предмета для сообщений: "Rare Golden Chicken (2.5 kg)"
function InventoryService.Describe(item)
	local mob = Mobs[item.MobId]
	local name = mob and mob.DisplayName or item.MobId
	local mutation = Mutations.Get(item.Mutation)
	if mutation.DisplayName ~= "" then
		name = mutation.DisplayName .. " " .. name
	end
	return Rarities.Get(item.Rarity).DisplayName .. " " .. name .. " (" .. Format.Weight(item.Weight) .. ")"
end

local function refresh(player, data)
	player:SetAttribute("EggCount", countKeys(data.Backpack.Eggs))
	player:SetAttribute("MobCount", countKeys(data.Backpack.Mobs))
	changedEvent:Fire(player)
end

---------------------------------------------------------------------
-- Сколько занято
---------------------------------------------------------------------

function InventoryService.CountEggs(player)
	local data = DataService.Get(player)
	return data and countKeys(data.Backpack.Eggs) or 0
end

function InventoryService.CountMobs(player)
	local data = DataService.Get(player)
	return data and countKeys(data.Backpack.Mobs) or 0
end

function InventoryService.HasEggSpace(player)
	return InventoryService.CountEggs(player) < GameConfig.Backpack.MaxEggs
end

function InventoryService.HasMobSpace(player)
	return InventoryService.CountMobs(player) < GameConfig.Backpack.MaxMobs
end

---------------------------------------------------------------------
-- Положить
---------------------------------------------------------------------

-- Кладёт готовый предмет в рюкзак. Возвращает номер предмета или nil, если места нет.
function InventoryService.AddEggItem(player, item)
	local data = DataService.Get(player)
	if not data or not item then
		return nil
	end
	if countKeys(data.Backpack.Eggs) >= GameConfig.Backpack.MaxEggs then
		Remotes.Notify(player, "Backpack full", "You can carry " .. GameConfig.Backpack.MaxEggs .. " eggs.")
		return nil
	end
	local id = nextItemId(data)
	data.Backpack.Eggs[id] = item
	refresh(player, data)
	return id
end

function InventoryService.AddMobItem(player, item)
	local data = DataService.Get(player)
	if not data or not item then
		return nil
	end
	if countKeys(data.Backpack.Mobs) >= GameConfig.Backpack.MaxMobs then
		Remotes.Notify(player, "Backpack full", "You can carry " .. GameConfig.Backpack.MaxMobs .. " mobs.")
		return nil
	end
	local id = nextItemId(data)
	data.Backpack.Mobs[id] = item
	refresh(player, data)
	return id
end

function InventoryService.AddEgg(player, mobId, rarity, weight)
	return InventoryService.AddEggItem(player, InventoryService.MakeItem(mobId, rarity, weight, "None"))
end

function InventoryService.AddMob(player, mobId, rarity, weight, mutation)
	return InventoryService.AddMobItem(player, InventoryService.MakeItem(mobId, rarity, weight, mutation))
end

---------------------------------------------------------------------
-- Достать
---------------------------------------------------------------------

function InventoryService.GetEgg(player, itemId)
	local data = DataService.Get(player)
	return data and data.Backpack.Eggs[itemId]
end

function InventoryService.GetMob(player, itemId)
	local data = DataService.Get(player)
	return data and data.Backpack.Mobs[itemId]
end

-- Вынимает предмет из рюкзака и возвращает его
function InventoryService.TakeEgg(player, itemId)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local item = data.Backpack.Eggs[itemId]
	if not item then
		return nil
	end
	data.Backpack.Eggs[itemId] = nil
	refresh(player, data)
	return item
end

function InventoryService.TakeMob(player, itemId)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local item = data.Backpack.Mobs[itemId]
	if not item then
		return nil
	end
	data.Backpack.Mobs[itemId] = nil
	refresh(player, data)
	return item
end

-- Самый старый предмет в рюкзаке (меньший номер = раньше получен).
-- Нужен, пока нет интерфейса выбора: слот берёт первое яйцо из рюкзака.
local function oldestId(tbl)
	local best, bestNumber
	for id in pairs(tbl) do
		local n = tonumber(id) or math.huge
		if not bestNumber or n < bestNumber then
			best, bestNumber = id, n
		end
	end
	return best
end

function InventoryService.OldestEggId(player)
	local data = DataService.Get(player)
	return data and oldestId(data.Backpack.Eggs)
end

function InventoryService.OldestMobId(player)
	local data = DataService.Get(player)
	return data and oldestId(data.Backpack.Mobs)
end

---------------------------------------------------------------------
-- Продажа
---------------------------------------------------------------------

function InventoryService.SellEgg(player, itemId)
	local item = InventoryService.GetEgg(player, itemId)
	if not item then
		return false
	end
	local price = Formulas.EggSellPrice(item)
	InventoryService.TakeEgg(player, itemId)
	EconomyService.AddMoney(player, price)
	Remotes.Notify(player, "Sold", InventoryService.Describe(item) .. " for $" .. Format.Number(price))
	return true
end

function InventoryService.SellMob(player, itemId)
	local item = InventoryService.GetMob(player, itemId)
	if not item then
		return false
	end
	local price = Formulas.MobSellPrice(item)
	InventoryService.TakeMob(player, itemId)
	EconomyService.AddMoney(player, price)
	Remotes.Notify(player, "Sold", InventoryService.Describe(item) .. " for $" .. Format.Number(price))
	return true
end

function InventoryService.Init()
	DataService.ProfileLoaded:Connect(function(player, data)
		refresh(player, data)
	end)
end

return InventoryService
