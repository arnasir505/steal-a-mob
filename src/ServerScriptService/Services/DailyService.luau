-- DailyService: ежедневный календарь наград.
--
-- Правила (награды и даты сезонов — Config/Seasons):
--  * в сезоне 30 наград, к концу они лучше;
--  * каждый новый день (с 00:00 UTC) открывает СЛЕДУЮЩУЮ награду. Пропуск дней
--    прогресс не сбрасывает: не заходил неделю — получишь просто следующую по порядку;
--  * за один день — одна награда;
--  * сезон ~35 дней (30 наград + 5 дней запаса). Начался новый сезон — прогресс
--    с нуля, незабранные награды старого сгорают. Между сезонами календаря нет.
--
-- Пока нет интерфейса (этап 11), награда забирается сама: через несколько секунд
-- после входа и в полночь, если игрок в игре (GameConfig.Daily.AutoClaim).
-- Для интерфейса:
--   Remotes.Event("ClaimDaily")   -- забрать сегодняшнюю награду
--   атрибуты игрока: DailySeason (Id сезона или ""), DailyClaimed (сколько забрано),
--   DailyCanClaim (можно ли забрать сейчас), DailyNextDayAt (когда откроется следующая, os.time)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Seasons = require(ReplicatedStorage.Shared.Config.Seasons)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local TrailService = require(script.Parent.TrailService)

local D = GameConfig.Daily

local SfxService = require(script.Parent.SfxService)

local DailyService = {}

-- Только для тестов в Studio: сдвиг времени (команда !daily skip),
-- чтобы проверить календарь, не дожидаясь полуночи и начала сезона
local testOffset = 0

local function now()
	return os.time() + testOffset
end

---------------------------------------------------------------------
-- Награды
---------------------------------------------------------------------

local function mobName(mobId)
	local mob = Mobs[mobId]
	return mob and mob.DisplayName or tostring(mobId)
end

-- Текст награды для сообщения
function DailyService.Describe(reward)
	if reward.Type == "Money" then
		return "+$" .. Format.Number(reward.Amount)
	elseif reward.Type == "Speed" then
		return "+" .. Format.Number(reward.Amount) .. " speed"
	elseif reward.Type == "Egg" or reward.Type == "Mob" then
		local rarity = Rarities.Get(reward.Rarity).DisplayName
		local suffix = reward.Type == "Egg" and " Egg" or ""
		return rarity .. " " .. mobName(reward.MobId) .. suffix .. " (" .. Format.Weight(reward.Weight or 1) .. ")"
	elseif reward.Type == "Trail" then
		local trail = Items.Trails[reward.TrailId]
		return (trail and trail.DisplayName or tostring(reward.TrailId)) .. " (trail)"
	end
	return "?"
end

-- Хватит ли места в рюкзаке. Если нет — награду не забираем, чтобы она не пропала.
local function hasSpace(player, reward)
	if reward.Type == "Egg" then
		return InventoryService.HasEggSpace(player)
	elseif reward.Type == "Mob" then
		return InventoryService.HasMobSpace(player)
	end
	return true
end

local function giveReward(player, data, reward)
	if reward.Type == "Money" then
		return EconomyService.AddMoney(player, reward.Amount)
	elseif reward.Type == "Speed" then
		return EconomyService.AddSpeed(player, reward.Amount)
	elseif reward.Type == "Egg" then
		return InventoryService.AddEgg(player, reward.MobId, reward.Rarity or "Common", reward.Weight or 1) ~= nil
	elseif reward.Type == "Mob" then
		return InventoryService.AddMob(player, reward.MobId, reward.Rarity or "Common",
			reward.Weight or 1, reward.Mutation or "None") ~= nil
	elseif reward.Type == "Trail" then
		if not TrailService.Grant(player, reward.TrailId) then
			return false
		end
		-- Надеваем, если он лучше того, что надет
		local new = Items.Trails[reward.TrailId]
		local current = Items.Trails[data.EquippedTrail]
		if not current or new.TreadmillMult > current.TreadmillMult then
			TrailService.Equip(player, reward.TrailId)
		end
		return true
	end
	return false
end

---------------------------------------------------------------------
-- Прогресс
---------------------------------------------------------------------

-- Прогресс относится к текущему сезону. Сезон сменился — начинаем с нуля.
local function syncSeason(data, season)
	local id = season and season.Id or ""
	if data.Daily.SeasonId ~= id then
		data.Daily.SeasonId = id
		data.Daily.Claimed = 0
		data.Daily.LastClaimDay = -1
	end
end

local function canClaim(data, season, today)
	return season ~= nil
		and data.Daily.Claimed < Seasons.DaysInCalendar
		and today > data.Daily.LastClaimDay
end

-- Атрибуты для интерфейса
local function refresh(player, data)
	local season = Seasons.GetActive(now())
	syncSeason(data, season)
	local today = Formulas.DayNumber(now())
	local dayLength = 24 * 60 * 60
	player:SetAttribute("DailySeason", data.Daily.SeasonId)
	player:SetAttribute("DailyClaimed", data.Daily.Claimed)
	player:SetAttribute("DailyCanClaim", canClaim(data, season, today))
	player:SetAttribute("DailyNextDayAt", (today + 1) * dayLength + D.ResetHourUTC * 3600 - testOffset)
end

-- Забрать сегодняшнюю награду. quiet = true — не сообщать, что забирать нечего.
function DailyService.Claim(player, quiet)
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local season = Seasons.GetActive(now())
	syncSeason(data, season)
	local today = Formulas.DayNumber(now())
	if not canClaim(data, season, today) then
		refresh(player, data)
		if not quiet then
			local text = not season and "No calendar right now."
				or data.Daily.Claimed >= Seasons.DaysInCalendar and "All rewards of this season claimed!"
				or "Come back tomorrow!"
			Remotes.Notify(player, "Daily reward", text)
		end
		return false
	end

	local day = data.Daily.Claimed + 1
	local reward = season.Rewards[day]
	if reward and not hasSpace(player, reward) then
		Remotes.Notify(player, "Backpack full", "Free up space to get your daily reward.")
		return false
	end
	if not reward or not giveReward(player, data, reward) then
		-- Ошибка в конфиге: не застреваем на этом дне навсегда
		warn("[DailyService] Сезон " .. season.Id .. ", день " .. day .. ": награда не выдана — проверь Config/Seasons")
	end

	data.Daily.Claimed = day
	data.Daily.LastClaimDay = today
	refresh(player, data)
	SfxService.PlayFor(player, "DailyReward")
	Remotes.Notify(player, "Daily reward — Day " .. day .. "/" .. Seasons.DaysInCalendar,
		reward and DailyService.Describe(reward) or "")
	return true
end

-- Строки для тестовой команды !daily
function DailyService.DebugLines(player)
	local data = DataService.Get(player)
	if not data then
		return { "данные не загружены" }
	end
	local season = Seasons.GetActive(now())
	syncSeason(data, season)
	local lines = {}
	local today = Formulas.DayNumber(now())
	table.insert(lines, "время: " .. DateTime.fromUnixTimestamp(now()):FormatUniversalTime("YYYY-MM-DD HH:mm", "en-us")
		.. " UTC" .. (testOffset ~= 0 and (" (сдвиг на " .. testOffset // 86400 .. " дн.)") or ""))
	if not season then
		local nextSeason
		for _, candidate in ipairs(Seasons.List) do
			if candidate.StartsAt > now() and (not nextSeason or candidate.StartsAt < nextSeason.StartsAt) then
				nextSeason = candidate
			end
		end
		table.insert(lines, "сейчас нет сезона" .. (nextSeason and (", " .. nextSeason.Id .. " начнётся "
			.. DateTime.fromUnixTimestamp(nextSeason.StartsAt):FormatUniversalTime("YYYY-MM-DD", "en-us")
			.. " (!daily skip " .. math.ceil((nextSeason.StartsAt - now()) / 86400) .. ")") or ""))
		return lines
	end
	table.insert(lines, string.format("сезон %s, забрано %d/%d, сегодня можно: %s",
		season.Id, data.Daily.Claimed, Seasons.DaysInCalendar,
		canClaim(data, season, today) and "да" or "нет"))
	local nextReward = season.Rewards[data.Daily.Claimed + 1]
	if nextReward then
		table.insert(lines, "следующая награда: " .. DailyService.Describe(nextReward))
	end
	return lines
end

-- Только для тестов
function DailyService.SkipDays(days)
	testOffset = testOffset + days * 24 * 60 * 60
end

function DailyService.ResetForTesting(player)
	local data = DataService.Get(player)
	if data then
		data.Daily.Claimed = 0
		data.Daily.LastClaimDay = -1
		refresh(player, data)
	end
end

-- Притвориться, что наступил новый день: сегодняшняя награда снова доступна
function DailyService.AllowAgainForTesting(player)
	local data = DataService.Get(player)
	if data then
		data.Daily.LastClaimDay = Formulas.DayNumber(now()) - 1
		refresh(player, data)
	end
end

function DailyService.Init()
	Remotes.Event("ClaimDaily").OnServerEvent:Connect(function(player)
		DailyService.Claim(player)
	end)

	DataService.ProfileLoaded:Connect(function(player, data)
		refresh(player, data)
		if D.AutoClaim then
			-- Чуть позже, чтобы клиент успел загрузиться и увидел сообщение
			task.delay(D.AutoClaimDelay, function()
				if player.Parent then
					DailyService.Claim(player, true)
				end
			end)
		end
	end)

	-- Полночь: у тех, кто в игре, открывается новая награда
	task.spawn(function()
		while true do
			task.wait(D.CheckInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = DataService.Get(player)
				if data then
					if D.AutoClaim then
						DailyService.Claim(player, true)
					else
						refresh(player, data)
					end
				end
			end
		end
	end)
end

return DailyService
