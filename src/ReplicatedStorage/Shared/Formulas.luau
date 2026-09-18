-- Formulas: все игровые формулы в одном месте.
-- Используется и сервером (настоящие расчёты), и клиентом (чтобы показывать цифры в интерфейсе).
--
-- "item" — это моб или яйцо:
--   { MobId = "Chicken", Rarity = "Rare", Weight = 1.5, Mutation = "None" }
-- Редкость принадлежит предмету, а не мобу: Курица бывает и Common, и Rare.

local Config = script.Parent.Config
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)
local Mobs = require(Config.Mobs)
local Biomes = require(Config.Biomes)

local W = GameConfig.Weight
local S = GameConfig.Speed
local T = GameConfig.Treadmill
local B = GameConfig.Base
local Fuse = GameConfig.Fuse
local Sell = GameConfig.Sell

local Formulas = {}

local function log10(x)
	return math.log10(math.max(x, 1))
end

local function clamp(x, lo, hi)
	return math.max(lo, math.min(hi, x))
end

---------------------------------------------------------------------
-- Вес
---------------------------------------------------------------------

function Formulas.ClampWeight(weight)
	return clamp(weight, W.Min, W.Max)
end

-- Случайный вес яйца при спавне в биоме: лёгкие часто, тяжёлые редко
function Formulas.RollSpawnWeight(rng)
	local x = rng:NextNumber() ^ W.SpawnRollPower
	local weight = 10 ^ (x * log10(W.SpawnMaxWeight))
	return math.floor(weight * 100) / 100 -- округляем до 0.01 кг
end

-- Во сколько раз увеличить модель
function Formulas.ModelScale(weight)
	local share = log10(Formulas.ClampWeight(weight)) / log10(W.Max)
	return 1 + share * (W.MaxModelScale - 1)
end

---------------------------------------------------------------------
-- Доход и вылупление
---------------------------------------------------------------------

function Formulas.WeightIncomeMultiplier(weight)
	return Formulas.ClampWeight(weight) ^ W.IncomeExponent
end

-- Деньги в секунду от одного моба (без геймпассов и бонуса друзей)
function Formulas.MobIncome(item)
	local mob = Mobs[item.MobId]
	if not mob then
		return 0
	end
	local rarity = Rarities.Get(item.Rarity)
	local mutation = Mutations.Get(item.Mutation)
	return mob.BaseIncome
		* rarity.IncomeMult
		* Formulas.WeightIncomeMultiplier(item.Weight)
		* mutation.IncomeMult
end

-- Время вылупления в секундах. hatchSpeedMult = 2 при геймпассе X2Hatch
function Formulas.HatchTime(item, hatchSpeedMult)
	local rarity = Rarities.Get(item.Rarity)
	local seconds = rarity.HatchTime * (1 + log10(item.Weight) * W.HatchTimePerLog)
	return seconds / (hatchSpeedMult or 1)
end

-- Случайная мутация при вылуплении
function Formulas.RollMutation(rng)
	local entries = {}
	for _, id in ipairs(Mutations.Order) do
		table.insert(entries, { Key = id, Weight = Mutations.Data[id].Chance })
	end
	return Formulas.WeightedPick(entries, rng)
end

-- Случайная редкость яйца при спавне.
-- biomeId необязателен. С ним выпадают только редкости из списка Rarities
-- этого биома, а их шансы делятся между собой по пропорции.
function Formulas.RollRarity(rng, biomeId)
	local biome = biomeId and Biomes.Get(biomeId)
	local allowed = biome and biome.Rarities
	local entries = {}
	for _, id in ipairs(allowed or Rarities.Order) do
		local data = Rarities.Data[id]
		if data then
			table.insert(entries, { Key = id, Weight = data.SpawnWeight })
		end
	end
	if #entries == 0 then
		warn("[Formulas] У биома " .. tostring(biomeId) .. " не указаны редкости")
		return Rarities.Order[1]
	end
	return Formulas.WeightedPick(entries, rng)
end

-- Случайный моб биома. Все мобы биома равноправны, пока не задан SpawnWeight.
local biomeMobCache = {}
local function mobsInBiome(biomeId)
	local cached = biomeMobCache[biomeId]
	if cached then
		return cached
	end
	local entries = {}
	for id, mob in pairs(Mobs) do
		if mob.Biome == biomeId then
			table.insert(entries, { Key = id, Weight = mob.SpawnWeight or 1 })
		end
	end
	table.sort(entries, function(a, b)
		return a.Key < b.Key -- одинаковый порядок на всех серверах
	end)
	biomeMobCache[biomeId] = entries
	return entries
end

function Formulas.RollMobId(rng, biomeId)
	local entries = mobsInBiome(biomeId)
	if #entries == 0 then
		warn("[Formulas] В биоме " .. tostring(biomeId) .. " нет мобов")
		return nil
	end
	return Formulas.WeightedPick(entries, rng)
end

-- Целое яйцо для спавна в биоме: кто внутри, какой редкости и сколько весит.
-- Мутации у яйца нет — она выпадает при вылуплении.
function Formulas.RollEgg(rng, biomeId)
	local mobId = Formulas.RollMobId(rng, biomeId)
	if not mobId then
		return nil
	end
	return {
		MobId = mobId,
		Rarity = Formulas.RollRarity(rng, biomeId),
		Weight = Formulas.RollSpawnWeight(rng),
	}
end

---------------------------------------------------------------------
-- Скорость
---------------------------------------------------------------------

-- Замедление от несомого яйца (1 = без замедления)
function Formulas.CarryMultiplier(weight)
	return math.max(W.MinCarryMultiplier, 1 - log10(weight) * W.CarrySlowPerLog)
end

-- Скорость, которая сравнивается со скоростью босса
function Formulas.EffectiveSpeed(speedStat, carriedWeight)
	if carriedWeight then
		return speedStat * Formulas.CarryMultiplier(carriedWeight)
	end
	return speedStat
end

-- Реальная скорость персонажа (Humanoid.WalkSpeed)
function Formulas.WalkSpeed(effectiveSpeed)
	return math.min(S.MaxWalkSpeed, S.BaseWalkSpeed + log10(effectiveSpeed) * S.WalkSpeedPerLog)
end

-- Реальная скорость босса в погоне: исход решают статы, а не реальная скорость
function Formulas.BossChaseWalkSpeed(playerEffectiveSpeed, bossSpeed, playerWalkSpeed)
	if playerEffectiveSpeed >= bossSpeed then
		return math.max(1, playerWalkSpeed - S.ChaseSpeedDelta) -- игрок убегает
	end
	return playerWalkSpeed + S.ChaseSpeedDelta -- босс догоняет
end

---------------------------------------------------------------------
-- Беговая дорожка и база
---------------------------------------------------------------------

-- Прибавка скорости за один шаг. multiplier = трейл x геймпасс x бонус друзей
function Formulas.TreadmillGain(level, multiplier)
	return (T.BaseGain + level * T.GainPerLevel) * (multiplier or 1)
end

-- Цена перехода с уровня level на level + 1
function Formulas.TreadmillUpgradeCost(level)
	return math.floor(T.UpgradeBaseCost * T.UpgradeCostGrowth ^ level)
end

-- Сколько мест на участке при данном уровне улучшения
function Formulas.BaseSlots(level)
	return math.min(B.MaxSlots, B.StartSlots + level * B.SlotsPerLevel)
end

-- Максимальный уровень улучшения: дальше слоты уже не добавляются
function Formulas.MaxBaseLevel()
	return math.ceil((B.MaxSlots - B.StartSlots) / B.SlotsPerLevel)
end

function Formulas.BaseUpgradeCost(level)
	return math.floor(B.UpgradeBaseCost * B.UpgradeCostGrowth ^ level)
end

---------------------------------------------------------------------
-- Продажа
---------------------------------------------------------------------

-- Цена продажи моба: его доход за несколько минут
function Formulas.MobSellPrice(item)
	return math.max(Sell.MinPrice, math.floor(Formulas.MobIncome(item) * Sell.MobSeconds))
end

-- Цена продажи яйца: дешевле, чем готовый моб (мутации ведь ещё нет)
function Formulas.EggSellPrice(item)
	return math.max(Sell.MinPrice, math.floor(Formulas.MobIncome(item) * Sell.MobSeconds * Sell.EggFactor))
end

---------------------------------------------------------------------
-- Бонусы
---------------------------------------------------------------------

-- 0.1 = +10%
function Formulas.FriendsBonus(friendCount)
	local cfg = GameConfig.FriendsBonus
	return math.min(cfg.Max, friendCount * cfg.PerFriend)
end

function Formulas.OfflineIncome(incomePerSecond, secondsAway, moneyMultiplier)
	local seconds = clamp(secondsAway, 0, GameConfig.Offline.MaxSeconds)
	return incomePerSecond * seconds * (moneyMultiplier or 1)
end

---------------------------------------------------------------------
-- Синтез
---------------------------------------------------------------------

-- Шанс получить более тяжёлого моба
function Formulas.FuseUpgradeChance(weight)
	local fullUntil = Fuse.FullChanceUntilWeight
	if weight <= fullUntil then
		return Fuse.BaseChance
	end
	local steps = (log10(weight) - log10(fullUntil)) / Fuse.ChanceHalvesEveryLog
	return Fuse.BaseChance * 0.5 ^ steps
end

-- Возвращает вес результата и true, если моб стал тяжелее
function Formulas.RollFuseResult(inputWeights, rng)
	local maxWeight = 0
	for _, weight in ipairs(inputWeights) do
		maxWeight = math.max(maxWeight, weight)
	end
	if maxWeight < W.Max and rng:NextNumber() < Formulas.FuseUpgradeChance(maxWeight) then
		local mult = rng:NextNumber(Fuse.MinResultMult, Fuse.MaxResultMult)
		local newWeight = math.floor(maxWeight * mult * 100) / 100
		return Formulas.ClampWeight(newWeight), true
	end
	return maxWeight, false
end

---------------------------------------------------------------------
-- Разное
---------------------------------------------------------------------

-- Номер дня для ежедневных наград (меняется в ResetHourUTC)
function Formulas.DayNumber(unixTime)
	local offset = GameConfig.Daily.ResetHourUTC * 3600
	return math.floor((unixTime - offset) / 86400)
end

-- Случайный выбор с весами. entries = { { Key = "A", Weight = 10 }, ... }
function Formulas.WeightedPick(entries, rng)
	local total = 0
	for _, entry in ipairs(entries) do
		total = total + entry.Weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in ipairs(entries) do
		roll = roll - entry.Weight
		if roll < 0 then
			return entry.Key
		end
	end
	return entries[#entries].Key
end

return Formulas
