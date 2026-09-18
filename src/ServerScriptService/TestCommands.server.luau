-- TestCommands: команды в чате для тестов. Работают ТОЛЬКО в Studio,
-- в опубликованной игре скрипт сразу выключается.
--
--   !money 1000            — дать денег
--   !speed 500             — дать скорости
--   !spend 300             — потратить деньги (проверка TrySpend)
--   !egg                   — положить в рюкзак случайное яйцо
--   !egg Cow Rare 500      — яйцо конкретного моба, редкости и веса (в любом порядке)
--   !mob Chicken Uncommon  — то же самое, но сразу мобом
--   !rarities              — показать шансы редкостей и мутаций
--   !sell                  — продать всё из рюкзака (или !sell eggs / !sell mobs)
--   !bag                   — показать рюкзак
--   !plot                  — показать участок
--   !hatch                 — вылупить все яйца на участке прямо сейчас
--   !slots 3               — поднять уровень участка бесплатно
--   !data                  — вывести все данные игрока в Output
--   !wipe                  — сбросить прогресс
--   !formulas              — вывести примеры формул в Output

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local InventoryService = require(Services.InventoryService)
local PlotService = require(Services.PlotService)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local Biomes = require(ReplicatedStorage.Shared.Config.Biomes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local rng = Random.new()

-- Ищет ключ в таблице, не различая большие и маленькие буквы ("cow" -> "Cow")
local function findKey(tbl, word)
	if tbl[word] then
		return word
	end
	local lower = string.lower(word)
	for key in pairs(tbl) do
		if string.lower(key) == lower then
			return key
		end
	end
	return nil
end

local function randomMobId()
	local ids = {}
	for id in pairs(Mobs) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids[rng:NextInteger(1, #ids)]
end

-- Разбирает "!egg Cow Rare 500": моб, редкость и вес в любом порядке
local function parseItemArgs(words)
	local mobId, rarity, weight
	for i = 2, #words do
		local word = words[i]
		if word ~= "" then
			local asMob = findKey(Mobs, word)
			local asRarity = findKey(Rarities.Data, word)
			if asMob then
				mobId = asMob
			elseif asRarity then
				rarity = asRarity
			elseif tonumber(word) then
				weight = tonumber(word)
			end
		end
	end
	mobId = mobId or randomMobId()
	local biomeId = Mobs[mobId] and Mobs[mobId].Biome
	rarity = rarity or Formulas.RollRarity(rng, biomeId)
	weight = weight or Formulas.RollSpawnWeight(rng)
	return mobId, rarity, weight
end

local function printFormulas()
	print("--- Formulas ---")
	for _, weight in ipairs({ 1, 10, 1000, 1000000, 100000000 }) do
		local item = { MobId = "Chicken", Rarity = "Common", Weight = weight, Mutation = "None" }
		print(string.format(
			"%s: income %s/s, sell $%s, hatch %s, scale x%.2f, carry x%.2f, fuse chance %.4f%%",
			Format.Weight(weight),
			Format.Number(Formulas.MobIncome(item)),
			Format.Number(Formulas.MobSellPrice(item)),
			Format.Time(Formulas.HatchTime(item)),
			Formulas.ModelScale(weight),
			Formulas.CarryMultiplier(weight),
			Formulas.FuseUpgradeChance(weight) * 100
		))
	end
	for _, speed in ipairs({ 1, 100, 10000, 1000000, 1000000000 }) do
		print("Speed " .. Format.Number(speed) .. " -> WalkSpeed " .. string.format("%.1f", Formulas.WalkSpeed(speed)))
	end
	print("Random egg weights:", Formulas.RollSpawnWeight(rng), Formulas.RollSpawnWeight(rng), Formulas.RollSpawnWeight(rng))
	print("Offline 3 days at 10/s:", Format.Number(Formulas.OfflineIncome(10, 3 * 86400)))
end

-- Показывает, как часто редкости появляются на самом деле.
-- В биоме выпадают только редкости из его списка Rarities, поэтому шансы там другие.
local function printRarities()
	print("--- Все редкости ---")
	for _, id in ipairs(Rarities.Order) do
		local data = Rarities.Data[id]
		print(string.format(
			"%-10s %6.2f%%  income x%-6s hatch %-8s %s",
			id,
			Rarities.SpawnChance(id) * 100,
			Format.Number(data.IncomeMult),
			Format.Time(data.HatchTime),
			data.Announce and "объявляется всем" or ""
		))
	end

	print("--- Мутации (выпадают при вылуплении) ---")
	local averageMult = 0
	for _, id in ipairs(Mutations.Order) do
		local data = Mutations.Data[id]
		local chance = Mutations.SpawnChance(id)
		averageMult = averageMult + chance * data.IncomeMult
		print(string.format(
			"%-8s %6.2f%%  income x%-4s ~1 раз в %d вылуплений  %s",
			id,
			chance * 100,
			Format.Number(data.IncomeMult),
			chance > 0 and math.floor(1 / chance) or 0,
			data.Announce and "объявляется всем" or ""
		))
	end
	print(string.format("Средний множитель дохода от мутаций: x%.2f", averageMult))

	local roundSeconds = GameConfig.Round.Duration
	for _, biome in ipairs(Biomes.List) do
		local eggs = biome.EggsAtOnce or 1
		local allowed = biome.Rarities or Rarities.Order
		local total = 0
		for _, id in ipairs(allowed) do
			total = total + Rarities.Get(id).SpawnWeight
		end

		local mobList = {}
		for id, mob in pairs(Mobs) do
			if mob.Biome == biome.Id then
				table.insert(mobList, id)
			end
		end
		table.sort(mobList)

		print(string.format("--- %s: %d яиц за раунд, раунд %s ---", biome.Id, eggs, Format.Time(roundSeconds)))
		print("  мобы: " .. (#mobList > 0 and table.concat(mobList, ", ") or "НЕТ МОБОВ"))
		for _, id in ipairs(allowed) do
			local chance = Rarities.Get(id).SpawnWeight / total
			local perRound = 1 - (1 - chance) ^ eggs
			print(string.format(
				"  %-10s %6.2f%% за яйцо | %6.2f%% за раунд | ~1 раз в %s",
				id, chance * 100, perRound * 100, Format.Time(roundSeconds / perRound)
			))
		end
	end
end

local function printBackpack(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	print("--- Backpack of " .. player.Name .. " ---")
	for id, item in pairs(data.Backpack.Eggs) do
		print("  egg #" .. id .. ": " .. InventoryService.Describe(item)
			.. " hatch " .. Format.Time(Formulas.HatchTime(item)))
	end
	for id, item in pairs(data.Backpack.Mobs) do
		print("  mob #" .. id .. ": " .. InventoryService.Describe(item)
			.. " = $" .. Format.Number(Formulas.MobIncome(item)) .. "/s")
	end
end

local function printPlot(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local used = 0
	for _ in pairs(data.Plot.Items) do
		used = used + 1
	end
	print(string.format("--- Plot of %s: %d/%d мест, уровень %d, доход $%s/s ---",
		player.Name, used, Formulas.BaseSlots(data.BaseLevel), data.BaseLevel,
		Format.Number(EconomyService.GetIncomePerSecond(player))))
	for id, placed in pairs(data.Plot.Items) do
		local extra = ""
		if placed.Type == "Egg" then
			extra = " hatches in " .. Format.Time((placed.HatchEndsAt or 0) - os.time())
		end
		print(string.format("  #%s %s %s at (%.1f, %.1f)%s",
			id, placed.Type, InventoryService.Describe(placed.Item), placed.X or 0, placed.Z or 0, extra))
	end
end

-- Продаёт содержимое рюкзака: !sell, !sell eggs, !sell mobs
local function sellBackpack(player, what)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local sold = 0
	if what ~= "mobs" then
		for id in pairs(table.clone(data.Backpack.Eggs)) do
			if InventoryService.SellEgg(player, id) then
				sold = sold + 1
			end
		end
	end
	if what ~= "eggs" then
		for id in pairs(table.clone(data.Backpack.Mobs)) do
			if InventoryService.SellMob(player, id) then
				sold = sold + 1
			end
		end
	end
	print("Продано предметов:", sold)
end

local function hatchAll(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	for id, placed in pairs(data.Plot.Items) do
		if placed.Type == "Egg" then
			PlotService.HatchNow(player, id)
		end
	end
end

local function onChatted(player, message)
	if string.sub(message, 1, 1) ~= "!" then
		return
	end
	local words = string.split(message, " ")
	local command = string.lower(string.sub(words[1], 2))
	local number = tonumber(words[2])

	if command == "money" and number then
		EconomyService.AddMoney(player, number)
	elseif command == "speed" and number then
		EconomyService.AddSpeed(player, number)
	elseif command == "spend" and number then
		print("TrySpend:", EconomyService.TrySpend(player, number))
	elseif command == "egg" or command == "mob" then
		local mobId, rarity, weight = parseItemArgs(words)
		if command == "egg" then
			InventoryService.AddEgg(player, mobId, rarity, weight)
		else
			InventoryService.AddMob(player, mobId, rarity, weight, Formulas.RollMutation(rng))
		end
		printBackpack(player)
	elseif command == "rarities" then
		printRarities()
	elseif command == "sell" then
		sellBackpack(player, words[2] and string.lower(words[2]) or nil)
	elseif command == "bag" then
		printBackpack(player)
	elseif command == "plot" then
		printPlot(player)
	elseif command == "hatch" then
		hatchAll(player)
		printPlot(player)
	elseif command == "slots" then
		local data = DataService.Get(player)
		if data then
			data.BaseLevel = math.clamp(data.BaseLevel + (number or 1), 0, Formulas.MaxBaseLevel())
			player:SetAttribute("Slots", Formulas.BaseSlots(data.BaseLevel))
			PlotService.RefreshPlot(player)
			print("Уровень участка:", data.BaseLevel, "мест:", Formulas.BaseSlots(data.BaseLevel))
		end
	elseif command == "data" then
		print(HttpService:JSONEncode(DataService.Get(player)))
	elseif command == "wipe" then
		DataService.ResetForTesting(player)
		EconomyService.Refresh(player)
		PlotService.RecalcIncome(player)
		PlotService.RefreshPlot(player)
		print("Data wiped for", player.Name)
	elseif command == "formulas" then
		printFormulas()
	end
end

local function onPlayerAdded(player)
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
