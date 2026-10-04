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
--   !treadmill 5           — поднять уровень дорожки бесплатно
--   !trail BlueTrail       — купить трейл (без имени — список трейлов)
--   !equip BlueTrail       — надеть трейл (!equip off — снять)
--   !speedinfo             — показать, из чего складывается скорость
--   !round                 — сбросить раунд прямо сейчас
--   !gates close / open    — закрыть или открыть ворота руками (проверить модель)
--   !eggs                  — показать яйца, которые сейчас лежат в биомах
--   !drop                  — бросить яйцо из рук (то же, что кнопка G)
--   !boss                  — что делают боссы и убежишь ли ты от них
--   !boss home             — все боссы на место и спать
--   !ragdoll               — упасть, как от толчка босса (проверить ragdoll)
--   !sword WoodenSword     — выдать и надеть меч (без имени — список, !sword off — убрать)
--   !index                 — показать индекс мобов и награды
--   !index Cow             — открыть одного моба (!index all — всех, чтобы получить мечи)
--   !index reset           — очистить индекс и забрать мечи, кроме начального
--   !fuse                  — синтез без машины: 3 самых дешёвых моба одного вида из рюкзака
--   !fuse Chicken          — то же, но только из Куриц
--   !friends 2             — притвориться, что на сервере 2 друга (!friends off — по-настоящему)
--   !daily                 — календарь: сезон, сколько забрано, следующая награда
--   !daily claim           — забрать сегодняшнюю награду
--   !daily next            — притвориться, что наступил новый день, и забрать награду
--   !daily skip 4          — сдвинуть время на 4 дня (например, до начала сезона)
--   !daily reset           — начать календарь сезона заново
--   !top                   — обновить общую таблицу лидеров и показать её
--   !buy                   — список донатов; !buy Money30Min / !buy X2Money — открыть окно покупки
--                            (нужен настоящий Id в Config/Products; в Studio покупка бесплатная)
--   !grant Money30Min      — выдать продукт без покупки, тем же путём, что и настоящая покупка
--   !pass X2Money          — притвориться, что геймпасс куплен
--   !sound UiClick         — проиграть звук (сначала только тебе, через секунду — в мире у тебя)
--   !where                 — где я: биом или safe zone
--   !tp Plains             — телепорт в центр биома (!tp home — на участок)
--   !time 20               — поставить время суток (0-24, без числа — показать)
--   !time stop             — остановить смену дня и ночи (!time go — запустить)
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
local SpeedService = require(Services.SpeedService)
local WorldService = require(Services.WorldService)
local EggService = require(Services.EggService)
local RoundService = require(Services.RoundService)
local BossService = require(Services.BossService)
local RagdollService = require(Services.RagdollService)
local SwordService = require(Services.SwordService)
local IndexService = require(Services.IndexService)
local FuseService = require(Services.FuseService)
local FriendsService = require(Services.FriendsService)
local DailyService = require(Services.DailyService)
local LeaderboardService = require(Services.LeaderboardService)
local TrailService = require(Services.TrailService)
local TimeChangeService = require(Services.TimeChangeService)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local Biomes = require(ReplicatedStorage.Shared.Config.Biomes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Products = require(ReplicatedStorage.Shared.Config.Products)
local PassService = require(Services.PassService)
local ProductService = require(Services.ProductService)
local SfxService = require(Services.SfxService)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

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
	weight = weight or Formulas.RollSpawnWeight(rng, biomeId)
	return mobId, rarity, weight
end

local function printFormulas()
	print("--- Formulas ---")
	for _, weight in ipairs({ 1, 2, 10, 100, 1000, 100000, 1000000, 100000000 }) do
		local item = { MobId = "Chicken", Rarity = "Common", Weight = weight, Mutation = "None" }
		print(string.format(
			"%s: income %s/s, sell $%s, hatch %s, scale x%.2f, egg x%.2f, carry x%.2f, fuse chance %.4f%%",
			Format.Weight(weight),
			Format.Number(Formulas.MobIncome(item)),
			Format.Number(Formulas.MobSellPrice(item)),
			Format.Time(Formulas.HatchTime(item)),
			Formulas.ModelScale(weight),
			Formulas.EggModelScale(weight),
			Formulas.CarryMultiplier(weight),
			Formulas.FuseUpgradeChance(weight) * 100
		))
	end
	for _, speed in ipairs({ 1, 10, 100, 1000, 1e6, 1e9, 1e12, 1e15, 1e18, 1e21 }) do
		local walkSpeed = Formulas.WalkSpeed(speed)
		print(string.format("Speed %-8s -> WalkSpeed %5.0f  (%.1f студа за кадр)",
			Format.Number(speed), walkSpeed, walkSpeed / 60))
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

local function printSpeedInfo(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	print("--- Speed of " .. player.Name .. " ---")
	print("  стата:            " .. Format.Number(data.Speed))
	print("  геймпасс x2:      " .. tostring(player:GetAttribute("Pass_X2Speed") == true))
	print("  вес яйца в руках: " .. Format.Number(player:GetAttribute("CarryWeight") or 0) .. " кг")
	print("  эффективная:      " .. Format.Number(SpeedService.GetEffectiveSpeed(player)))
	print("  WalkSpeed:        " .. string.format("%.1f", SpeedService.GetWalkSpeed(player))
		.. " (предел " .. GameConfig.Speed.MaxWalkSpeed .. ")")
	print("  дорожка ур." .. data.TreadmillLevel .. ": +" .. Format.Number(SpeedService.GetTreadmillGain(player)) .. "/сек"
		.. " (трейл x" .. TrailService.GetMultiplier(player)
		.. ", друзья x" .. string.format("%.1f", 1 + FriendsService.GetBonus(player)) .. ")")
	print("  трейл:            " .. (data.EquippedTrail ~= "" and data.EquippedTrail or "нет"))
end

local function printTrails(player)
	local data = DataService.Get(player)
	print("--- Trails ---")
	for id, config in pairs(Items.Trails) do
		local owned = data and data.Trails[id] and " (куплен)" or ""
		print(string.format("  %-14s $%-10s дорожка x%s%s",
			id, Format.Number(config.Price), config.TreadmillMult, owned))
	end
end

local function printSwords(player)
	local data = DataService.Get(player)
	print("--- Swords ---")
	for id, config in pairs(Items.Swords) do
		local owned = data and data.Swords[id] and " (есть)" or ""
		local equipped = data and data.EquippedSword == id and " [в руках]" or ""
		print(string.format("  %-14s толчок %s%s%s", id, Format.Number(config.Knockback), owned, equipped))
	end
end

local function printIndex(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	print("--- Index ---")
	for _, biome in ipairs(Biomes.List) do
		local opened, total = Formulas.IndexProgress(data.Index, biome.Id)
		local reward = biome.SwordReward and Items.Swords[biome.SwordReward]
		local got = biome.SwordReward and data.Swords[biome.SwordReward]
		print(string.format("  %s: %d/%d, награда: %s%s", biome.Id, opened, total,
			reward and reward.DisplayName or "нет", got and " (получена)" or ""))
		local marks = {}
		for _, mobId in ipairs(Formulas.BiomeMobIds(biome.Id)) do
			table.insert(marks, (data.Index[mobId] and "[x] " or "[ ] ") .. mobId)
		end
		print("    " .. table.concat(marks, "   "))
	end
end

local function printEggs()
	print("--- Яйца в мире (раунд кончится через " .. Format.Time(RoundService.GetSecondsLeft()) .. ") ---")
	local list = EggService.GetActive()
	if #list == 0 then
		print("  пусто")
	end
	for _, egg in ipairs(list) do
		print(string.format("  #%s %s в биоме %s%s",
			egg.Id,
			InventoryService.Describe(egg.Item),
			egg.BiomeId,
			egg.Carrier and (" — несёт " .. egg.Carrier.Name)
				or egg.HeldByBoss and " — несёт босс"
				or ""))
	end
end

local function printWhere(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local biome = WorldService.GetPlayerBiome(player)
	if WorldService.IsPlayerInSafeZone(player) then
		print(player.Name .. ": в safe zone")
	elseif biome then
		print(player.Name .. ": в биоме " .. biome.Id)
	else
		print(player.Name .. ": ни в safe zone, ни в биоме")
	end
	for _, line in ipairs(WorldService.DebugReport(root.Position)) do
		print("  " .. line)
	end
end

local function teleportTo(player, word)
	local character = player.Character
	if not character then
		return
	end
	if word == nil or string.lower(word) == "home" then
		PlotService.SendHome(player)
		return
	end
	local biome
	for _, candidate in ipairs(WorldService.GetBiomes()) do
		if string.lower(candidate.Id) == string.lower(word) then
			biome = candidate
			break
		end
	end
	if not biome then
		print("Биом не найден:", word)
		return
	end
	local box = biome.Boxes[1]
	character:PivotTo(box.CFrame * CFrame.new(0, -box.Size.Y / 2 + 5, 0))
	SpeedService.MarkTeleport(player)
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
	elseif command == "treadmill" then
		local data = DataService.Get(player)
		if data then
			data.TreadmillLevel = math.clamp(data.TreadmillLevel + (number or 1), 0, GameConfig.Treadmill.MaxLevel)
			player:SetAttribute("TreadmillLevel", data.TreadmillLevel)
			printSpeedInfo(player)
		end
	elseif command == "trail" then
		local id = words[2] and findKey(Items.Trails, words[2])
		if id then
			TrailService.Buy(player, id)
		end
		printTrails(player)
	elseif command == "equip" then
		local word = words[2]
		if word == nil or string.lower(word) == "off" then
			TrailService.Equip(player, "")
		else
			TrailService.Equip(player, findKey(Items.Trails, word) or word)
		end
		printSpeedInfo(player)
	elseif command == "speedinfo" then
		printSpeedInfo(player)
	elseif command == "round" then
		RoundService.ForceReset()
		print("Раунд сброшен")
	elseif command == "gates" then
		local close = words[2] == nil or string.lower(words[2]) ~= "open"
		WorldService.SetGatesClosed(close)
		print("Ворота " .. (close and "закрыты" or "открыты"))
	elseif command == "eggs" then
		printEggs()
	elseif command == "friends" then
		local word = words[2] and string.lower(words[2])
		if word == "off" then
			FriendsService.SetTestCount(player, nil)
		elseif number then
			FriendsService.SetTestCount(player, math.max(0, math.floor(number)))
		end
		print(string.format("Друзей на сервере: %d, бонус +%d%% к доходу и дорожке",
			FriendsService.GetCount(player), math.floor(FriendsService.GetBonus(player) * 100 + 0.5)))
	elseif command == "daily" then
		local word = words[2] and string.lower(words[2])
		if word == "claim" then
			DailyService.Claim(player)
		elseif word == "next" then
			DailyService.AllowAgainForTesting(player)
			DailyService.Claim(player)
		elseif word == "skip" then
			DailyService.SkipDays(tonumber(words[3]) or 1)
		elseif word == "reset" then
			DailyService.ResetForTesting(player)
		end
		print("--- Daily ---")
		for _, line in ipairs(DailyService.DebugLines(player)) do
			print("  " .. line)
		end
	elseif command == "top" then
		print("--- Top income / s (все серверы) ---")
		local top = LeaderboardService.Update()
		if #top == 0 then
			print("  пусто (или нет доступа к DataStore — см. предупреждение выше)")
		end
		for _, entry in ipairs(top) do
			print(string.format("  #%d %s — $%s/s", entry.Rank, entry.Name, Format.Number(entry.Income)))
		end
	elseif command == "fuse" then
		local mobId = words[2] and findKey(Mobs, words[2])
		if words[2] and not mobId then
			print("Нет такого моба:", words[2])
		else
			local item, upgraded = FuseService.FuseAuto(player, mobId)
			if item then
				print("Синтез:", InventoryService.Describe(item), upgraded and "(стал тяжелее!)" or "")
			end
			printBackpack(player)
		end
	elseif command == "index" then
		local word = words[2] and string.lower(words[2])
		if word == "all" then
			for mobId in pairs(Mobs) do
				IndexService.Discover(player, mobId)
			end
		elseif word == "reset" then
			local data = DataService.Get(player)
			if data then
				data.Index = {}
				data.Swords = {}
				data.EquippedSword = ""
				SwordService.GiveStarter(player)
				SwordService.Equip(player, data.EquippedSword)
			end
		elseif word then
			local mobId = findKey(Mobs, words[2])
			if mobId then
				IndexService.Discover(player, mobId)
			else
				print("Нет такого моба:", words[2])
			end
		end
		printIndex(player)
	elseif command == "sound" then
		local name = words[2] and findKey(Sounds.List, words[2])
		if not name then
			print("Звуки:", table.concat((function()
				local list = {}
				for key, config in pairs(Sounds.List) do
					local note = ""
					if config.Id == 0 then
						note = Sounds.Resolve(key) and "(запасной " .. tostring(config.Fallback) .. ")" or "(нет Id)"
					end
					table.insert(list, key .. note)
				end
				table.sort(list)
				return list
			end)(), ", "))
		else
			local resolved = Sounds.Resolve(name)
			print("Играю " .. name .. " (" .. (resolved and resolved.SoundId or "нет Id") .. ")")
			SfxService.PlayFor(player, name)
			task.delay(1, function()
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				SfxService.PlayAt(root, name)
			end)
		end
	elseif command == "buy" or command == "grant" or command == "pass" then
		local word = words[2]
		local passName = word and findKey(Products.GamePasses, word)
		local productName = word and findKey(Products.DevProducts, word)
		if command == "buy" and passName then
			ProductService.PromptPass(player, passName)
		elseif command == "buy" and productName then
			ProductService.PromptProduct(player, productName)
		elseif command == "grant" and productName then
			print("Выдача " .. productName .. ":", ProductService.GrantForTesting(player, productName))
		elseif command == "pass" and passName then
			PassService.GrantForTesting(player, passName)
			print("Тестовый геймпасс " .. passName .. " включён до выхода из игры."
				.. " Настоящий, купленный за Robux, действует навсегда.")
		else
			print("--- Donations ---")
			for name, pass in pairs(Products.GamePasses) do
				print(string.format("  геймпасс %-14s Id %-12s куплен: %s", name, tostring(pass.Id),
					tostring(PassService.Has(player, name))))
			end
			for name, product in pairs(Products.DevProducts) do
				print(string.format("  продукт  %-14s Id %s", name, tostring(product.Id)))
			end
			local data = DataService.Get(player)
			print("  зарядов мгновенного вылупления:", data and data.InstantHatches or 0)
		end
	elseif command == "sword" then
		local word = words[2]
		if word and string.lower(word) == "off" then
			SwordService.Equip(player, "")
		elseif word then
			local id = findKey(Items.Swords, word)
			if id then
				SwordService.Grant(player, id)
				SwordService.Equip(player, id)
			else
				print("Нет такого меча:", word)
			end
		end
		printSwords(player)
	elseif command == "ragdoll" then
		-- Толчок как будто спереди: игрок падает назад
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			RagdollService.Ragdoll(player, GameConfig.Boss.RagdollTime)
			SpeedService.Knockback(player, root.Position + root.CFrame.LookVector * 5, 60)
		end
	elseif command == "drop" then
		print("Бросил яйцо:", EggService.RequestDrop(player))
	elseif command == "boss" then
		if words[2] and string.lower(words[2]) == "home" then
			BossService.ResetAll()
		end
		print("--- Боссы ---")
		for _, line in ipairs(BossService.DebugLines(player)) do
			print("  " .. line)
		end
	elseif command == "where" then
		printWhere(player)
	elseif command == "tp" then
		teleportTo(player, words[2])
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
	elseif command == "time" then
		local word = string.lower(words[2] or "")
		if number then
			TimeChangeService.SetClockTime(number)
		elseif word == "stop" or word == "go" then
			TimeChangeService.SetEnabled(word == "go")
		end
		print(string.format(
			"ClockTime: %.2f (%s), running: %s",
			TimeChangeService.GetClockTime(),
			game:GetService("Lighting").TimeOfDay,
			tostring(TimeChangeService.IsEnabled())
		))
	elseif command == "data" then
		print(HttpService:JSONEncode(DataService.Get(player)))
	elseif command == "wipe" then
		DataService.ResetForTesting(player)
		local data = DataService.Get(player)
		EconomyService.Refresh(player)
		-- Сервисы узнают об изменениях по атрибутам игрока. Сброс данных их не трогает,
		-- поэтому обновляем сами — иначе модель дорожки и число мест остались бы старыми
		if data then
			player:SetAttribute("TreadmillLevel", data.TreadmillLevel) -- модель дорожки уровня 0
			player:SetAttribute("Slots", Formulas.BaseSlots(data.BaseLevel))
		end
		TrailService.Equip(player, "")   -- снять трейл
		SwordService.GiveStarter(player) -- начальный меч, как у нового игрока
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
