-- IndexService: индекс мобов — коллекция открытых мобов.
--
--  * моб открывается, как только у игрока появляется ЛЮБОЙ такой моб:
--    вылупился на участке или попал в рюкзак (тестовая команда, синтез на этапе 8).
--    Считается по мобу, а не по редкости: чтобы открыть Курицу, хватит любой Курицы;
--  * открыл всех мобов биома — получает меч-награду (SwordReward в Config/Biomes).
--    Меч выдаётся один раз и сам надевается, если он сильнее надетого;
--  * мобы, которые у игрока уже были до индекса (в рюкзаке или на участке),
--    засчитываются при входе в игру — вместе с наградами.
--
-- Данные: data.Index = { [MobId] = true }.
-- Прогресс по биому считает Formulas.IndexProgress — его можно звать и на клиенте.
-- Для интерфейса (этап 11):
--   Remotes.Function("GetIndex")  -- вернёт { [MobId] = true } открытых мобов
--   Remotes.Event("IndexUpdated") -- сервер сообщает клиенту: открыт новый моб (mobId)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Biomes = require(ReplicatedStorage.Shared.Config.Biomes)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)
local Items = require(ReplicatedStorage.Shared.Config.Items)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local PlotService = require(script.Parent.PlotService)
local SwordService = require(script.Parent.SwordService)

local IndexService = {}

local updatedEvent -- Remotes.Event("IndexUpdated")

local function biomeName(biome)
	return biome.DisplayName or biome.Id
end

-- Весь биом открыт — выдаём меч. Меч, который уже есть, второй раз не выдаётся.
local function checkReward(player, data, biome)
	local reward = biome.SwordReward
	if not reward or data.Swords[reward] or not Items.Swords[reward] then
		return
	end
	local opened, total = Formulas.IndexProgress(data.Index, biome.Id)
	if total == 0 or opened < total then
		return
	end
	SwordService.Grant(player, reward, true)
	Remotes.Notify(player, biomeName(biome) .. " Index complete!",
		"Reward: " .. Items.Swords[reward].DisplayName)
end

-- Открыть моба в индексе. Возвращает true, если он новый.
function IndexService.Discover(player, mobId)
	local data = DataService.Get(player)
	local mob = Mobs[mobId]
	if not data or not mob or data.Index[mobId] then
		return false
	end
	data.Index[mobId] = true
	updatedEvent:FireClient(player, mobId)

	local biome = Biomes.Get(mob.Biome)
	local text = mob.DisplayName or mobId
	if biome then
		local opened, total = Formulas.IndexProgress(data.Index, biome.Id)
		text = text .. " — " .. biomeName(biome) .. " " .. opened .. "/" .. total
	end
	Remotes.Notify(player, "New in Index!", text)

	if biome then
		checkReward(player, data, biome)
	end
	return true
end

function IndexService.Has(player, mobId)
	local data = DataService.Get(player)
	return data ~= nil and data.Index[mobId] == true
end

-- Сколько мобов биома открыто: открыто, всего
function IndexService.GetProgress(player, biomeId)
	local data = DataService.Get(player)
	if not data then
		return 0, 0
	end
	return Formulas.IndexProgress(data.Index, biomeId)
end

-- При входе: засчитываем мобов, которые уже есть у игрока, и выдаём
-- награды, которые он заработал, но не получил (например, до этого этапа)
local function catchUp(player, data)
	local function mark(item)
		if item and Mobs[item.MobId] then
			data.Index[item.MobId] = true
		end
	end
	for _, item in pairs(data.Backpack.Mobs) do
		mark(item)
	end
	for _, placed in pairs(data.Plot.Items) do
		if placed.Type == "Mob" then
			mark(placed.Item)
		end
	end
	for _, biome in ipairs(Biomes.List) do
		checkReward(player, data, biome)
	end
end

function IndexService.Init()
	updatedEvent = Remotes.Event("IndexUpdated")
	Remotes.Function("GetIndex").OnServerInvoke = function(player)
		local data = DataService.Get(player)
		return data and table.clone(data.Index) or {}
	end

	-- Моб вылупился на участке или попал в рюкзак
	PlotService.MobHatched:Connect(function(player, item)
		IndexService.Discover(player, item.MobId)
	end)
	InventoryService.MobAdded:Connect(function(player, item)
		IndexService.Discover(player, item.MobId)
	end)

	DataService.ProfileLoaded:Connect(catchUp)

	-- Подсказка автору: награда биома указана, а такого меча нет
	for _, biome in ipairs(Biomes.List) do
		if biome.SwordReward and not Items.Swords[biome.SwordReward] then
			warn("[IndexService] У биома " .. biome.Id .. " награда " .. biome.SwordReward
				.. ", но такого меча нет в Config/Items")
		end
	end
end

return IndexService
