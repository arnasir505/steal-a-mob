-- TestCommands: команды в чате для тестов. Работают ТОЛЬКО в Studio,
-- в опубликованной игре скрипт сразу выключается.
--
--   !money 1000            — дать денег
--   !speed 500             — дать скорости
--   !spend 300             — потратить деньги (проверка TrySpend)
--   !egg [MobId] [вес]     — положить яйцо в рюкзак (без аргументов — случайное)
--   !mob [MobId] [вес]     — положить моба в рюкзак
--   !bag                   — показать рюкзак
--   !plot                  — показать участок
--   !hatch                 — вылупить все яйца на участке прямо сейчас
--   !slots 3               — открыть слоты бесплатно
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
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local rng = Random.new()

local function randomMobId()
	local ids = {}
	for id in pairs(Mobs) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids[rng:NextInteger(1, #ids)]
end

local function printFormulas()
	print("--- Formulas ---")
	for _, weight in ipairs({ 1, 10, 1000, 1000000, 100000000 }) do
		local item = { MobId = "Chicken", Weight = weight, Mutation = "None" }
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
	print("Random rarity:", Formulas.RollRarity(rng), "Random mutation:", Formulas.RollMutation(rng))
	print("Offline 3 days at 10/s:", Format.Number(Formulas.OfflineIncome(10, 3 * 86400)))
end

local function printBackpack(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	print("--- Backpack of " .. player.Name .. " ---")
	for id, item in pairs(data.Backpack.Eggs) do
		print("  egg #" .. id .. ": " .. InventoryService.Describe(item))
	end
	for id, item in pairs(data.Backpack.Mobs) do
		print("  mob #" .. id .. ": " .. InventoryService.Describe(item) .. " = $" .. Format.Number(Formulas.MobIncome(item)) .. "/s")
	end
end

local function printPlot(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	print("--- Plot of " .. player.Name .. " (" .. Formulas.BaseSlots(data.BaseLevel) .. " slots, income $"
		.. Format.Number(EconomyService.GetIncomePerSecond(player)) .. "/s) ---")
	for key, slot in pairs(data.Plot.Slots) do
		local extra = ""
		if slot.Type == "Egg" then
			extra = " hatches in " .. Format.Time((slot.HatchEndsAt or 0) - os.time())
		end
		print("  slot " .. key .. ": " .. slot.Type .. " " .. InventoryService.Describe(slot.Item) .. extra)
	end
end

local function hatchAll(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	for key, slot in pairs(data.Plot.Slots) do
		if slot.Type == "Egg" then
			PlotService.HatchNow(player, tonumber(key))
		end
	end
end

local function onChatted(player, message)
	if string.sub(message, 1, 1) ~= "!" then
		return
	end
	local words = string.split(string.lower(message), " ")
	local command = string.sub(words[1], 2)
	local rawWords = string.split(message, " ")
	local argument = rawWords[2]
	local number = tonumber(words[2])

	if command == "money" and number then
		EconomyService.AddMoney(player, number)
	elseif command == "speed" and number then
		EconomyService.AddSpeed(player, number)
	elseif command == "spend" and number then
		print("TrySpend:", EconomyService.TrySpend(player, number))
	elseif command == "egg" or command == "mob" then
		local mobId = (argument and Mobs[argument]) and argument or randomMobId()
		local weight = tonumber(rawWords[3]) or Formulas.RollSpawnWeight(rng)
		if command == "egg" then
			InventoryService.AddEgg(player, mobId, weight)
		else
			InventoryService.AddMob(player, mobId, weight, Formulas.RollMutation(rng))
		end
		printBackpack(player)
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
			local add = number or 1
			data.BaseLevel = math.min(GameConfig.Base.MaxSlots - GameConfig.Base.StartSlots, data.BaseLevel + add)
			player:SetAttribute("Slots", Formulas.BaseSlots(data.BaseLevel))
			PlotService.RefreshPlot(player)
			print("Slots:", Formulas.BaseSlots(data.BaseLevel))
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
