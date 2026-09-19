-- EconomyService: деньги, скорость, таблица лидеров и офлайн-доход.
-- Любое изменение денег и скорости проходит ТОЛЬКО через этот сервис.
--
--   EconomyService.AddMoney(player, 100)
--   EconomyService.TrySpend(player, 500)   -> true, если хватило денег
--   EconomyService.AddSpeed(player, 10)
--   EconomyService.SetIncomePerSecond(player, 42)
--   EconomyService.GetMoneyMultiplier(player) -> 1 или 2 (геймпасс x2 деньги)
--
-- Клиент может читать значения через атрибуты игрока:
--   player:GetAttribute("Money"), "Speed", "IncomePerSecond", "OfflineEarned"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)

local EconomyService = {}

local incomePerSecond = {} -- [player] = число (не сохраняется, пересчитывается)
local moneyMultiplier = {} -- [player] = множитель денег от геймпассов

local INCOME_STAT = "Income/s"
local MONEY_STAT = "Money"
local SPEED_STAT = "Speed"

local function isValidAmount(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function createLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats" -- именно такое имя, иначе Roblox не покажет таблицу

	-- Первая колонка — доход в секунду (по нему лидерборд)
	local income = Instance.new("StringValue")
	income.Name = INCOME_STAT
	income.Value = "0"
	income.Parent = leaderstats

	local money = Instance.new("StringValue")
	money.Name = MONEY_STAT
	money.Value = "0"
	money.Parent = leaderstats

	local speed = Instance.new("StringValue")
	speed.Name = SPEED_STAT
	speed.Value = "1"
	speed.Parent = leaderstats

	leaderstats.Parent = player
end

-- Обновляет всё, что видит клиент
function EconomyService.Refresh(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	player:SetAttribute("Money", data.Money)
	player:SetAttribute("Speed", data.Speed)
	player:SetAttribute("IncomePerSecond", incomePerSecond[player] or 0)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats[MONEY_STAT].Value = Format.Number(data.Money)
		leaderstats[INCOME_STAT].Value = Format.Number(incomePerSecond[player] or 0)
		leaderstats[SPEED_STAT].Value = Format.Number(data.Speed)
	end
end

function EconomyService.GetMoney(player)
	local data = DataService.Get(player)
	return data and data.Money or 0
end

function EconomyService.AddMoney(player, amount)
	local data = DataService.Get(player)
	if not data or not isValidAmount(amount) or amount <= 0 then
		return false
	end
	data.Money = data.Money + amount
	data.Stats.TotalEarned = data.Stats.TotalEarned + amount
	EconomyService.Refresh(player)
	return true
end

function EconomyService.TrySpend(player, amount)
	local data = DataService.Get(player)
	if not data or not isValidAmount(amount) or amount < 0 then
		return false
	end
	if data.Money < amount then
		return false
	end
	data.Money = data.Money - amount
	EconomyService.Refresh(player)
	return true
end

function EconomyService.GetSpeed(player)
	local data = DataService.Get(player)
	return data and data.Speed or 1
end

function EconomyService.AddSpeed(player, amount)
	local data = DataService.Get(player)
	if not data or not isValidAmount(amount) or amount <= 0 then
		return false
	end
	data.Speed = data.Speed + amount
	EconomyService.Refresh(player)
	return true
end

-- Доход от мобов на участке без геймпассов и бонуса друзей
function EconomyService.CalculateBaseIncome(data)
	local total = 0
	for _, placed in pairs(data.Plot.Items) do
		if placed.Type == "Mob" then
			total = total + Formulas.MobIncome(placed.Item)
		end
	end
	return total
end

-- Итоговый доход в секунду задаёт сервис участков (этап 2)
function EconomyService.SetIncomePerSecond(player, value)
	if not isValidAmount(value) then
		return
	end
	incomePerSecond[player] = value
	EconomyService.Refresh(player)
end

function EconomyService.GetIncomePerSecond(player)
	return incomePerSecond[player] or 0
end

-- Множитель денег. Пока это только геймпасс x2;
-- бонус друзей добавим на этапе 9 (на офлайн-доход он не действует).
-- Значение считается заранее, чтобы в цикле дохода не ходить в интернет каждую секунду.
function EconomyService.RefreshMoneyMultiplier(player)
	local multiplier = PassService.Has(player, "X2Money") and 2 or 1
	moneyMultiplier[player] = multiplier
	return multiplier
end

function EconomyService.GetMoneyMultiplier(player)
	return moneyMultiplier[player] or 1
end

-- Офлайн-доход: без бонуса друзей, с геймпассом X2Money, максимум 2 дня.
-- Вызывает PlotService при загрузке игрока — ДО того, как вылупятся яйца,
-- чтобы деньги начислились только за мобов, которые уже стояли на участке.
function EconomyService.ApplyOfflineIncome(player, baseIncome)
	local seconds = DataService.GetOfflineSeconds(player)
	if seconds <= 0 or baseIncome <= 0 then
		return 0
	end
	local earned = Formulas.OfflineIncome(baseIncome, seconds, EconomyService.RefreshMoneyMultiplier(player))
	if earned > 0 then
		EconomyService.AddMoney(player, earned)
		player:SetAttribute("OfflineEarned", earned) -- интерфейс покажет окно "Пока тебя не было..."
	end
	return earned
end

local function onProfileLoaded(player)
	createLeaderstats(player)
	EconomyService.Refresh(player)
	task.spawn(EconomyService.RefreshMoneyMultiplier, player)
end

function EconomyService.Init()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	PassService.PassGranted:Connect(function(player)
		EconomyService.RefreshMoneyMultiplier(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		incomePerSecond[player] = nil
		moneyMultiplier[player] = nil
	end)
end

return EconomyService
