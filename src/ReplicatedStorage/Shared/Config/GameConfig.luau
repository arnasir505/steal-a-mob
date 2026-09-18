-- GameConfig: общие настройки игры.
-- ВСЕ ЧИСЛА ЗДЕСЬ ВРЕМЕННЫЕ. Меняй их при балансе — код трогать не нужно.

local GameConfig = {}

-- Имя хранилища данных. Если поменять, у всех игроков начнётся новый прогресс.
GameConfig.DataStoreName = "PlayerData_v1"

-- Как часто сохранять данные игроков (секунды)
GameConfig.AutosaveInterval = 60

-- Раунды: каждые 5 минут всех выкидывает в safe zone и яйца обновляются
GameConfig.Round = {
	Duration = 5 * 60,   -- длина раунда
	WarningBefore = 10,  -- за сколько секунд предупреждать о сбросе
}

-- Вес мобов и яиц
GameConfig.Weight = {
	Min = 1,                 -- 1 кг
	Max = 100000000,         -- 100 млн кг
	IncomeExponent = 0.5,    -- доход растёт как вес^0.5 (1 кг = x1, 100 кг = x10, 100 млн кг = x10000)
	HatchTimePerLog = 0.15,  -- +15% ко времени вылупления за каждые x10 веса
	MaxModelScale = 5,       -- модель самого тяжёлого моба в 5 раз больше модели 1 кг
	CarrySlowPerLog = 0.08,  -- -8% скорости за каждые x10 веса несомого яйца
	MinCarryMultiplier = 0.3,-- яйцо не может замедлить сильнее, чем до 30%
	SpawnMaxWeight = 1000,   -- самое тяжёлое яйцо, которое может заспавниться в биоме
	SpawnRollPower = 4,      -- чем больше число, тем реже спавнятся тяжёлые яйца
}

-- Скорость игрока
GameConfig.Speed = {
	StartStat = 1,           -- игрок начинает со скорости 1
	BaseWalkSpeed = 16,      -- реальная скорость персонажа при стате 1 (стандарт Roblox)
	WalkSpeedPerLog = 8,     -- +8 к реальной скорости за каждые x10 статы
	MaxWalkSpeed = 100,      -- предел реальной скорости, чтобы не пролетать сквозь стены
	ChaseSpeedDelta = 2,     -- на сколько босс медленнее/быстрее игрока во время погони
}

-- Беговая дорожка (прибавка обычными числами, не процентами)
GameConfig.Treadmill = {
	BaseGain = 1,            -- скорость за один шаг на уровне 0
	GainPerLevel = 1,        -- +1 к прибавке за каждый уровень улучшения
	UpgradeBaseCost = 100,   -- цена первого улучшения
	UpgradeCostGrowth = 1.5, -- каждое следующее улучшение дороже в 1.5 раза
	MaxLevel = 100,
}

-- Участок (база)
-- Участок улучшается целиком: одно улучшение даёт сразу несколько слотов
-- и делает забор красивее.
GameConfig.Base = {
	StartSlots = 2,          -- сколько мест на участке в самом начале
	SlotsPerLevel = 2,       -- сколько мест добавляет одно улучшение
	MaxSlots = 40,           -- предел
	UpgradeBaseCost = 500,
	UpgradeCostGrowth = 2.2, -- каждое следующее улучшение дороже в 2.2 раза
}

-- Рюкзак
GameConfig.Backpack = {
	MaxEggs = 1000,
	MaxMobs = 1000,
}

-- Машина синтеза
GameConfig.Fuse = {
	InputCount = 3,              -- сколько одинаковых мобов нужно
	BaseChance = 0.05,           -- 5% шанс получить более тяжёлого моба
	FullChanceUntilWeight = 10,  -- до 10 кг шанс полный
	ChanceHalvesEveryLog = 1,    -- дальше шанс падает вдвое за каждые x10 веса
	MinResultMult = 1.5,         -- тяжёлый результат = самый тяжёлый моб x (1.5 ... 3)
	MaxResultMult = 3,
}

-- Бонус за друзей на сервере (доход и тренировка скорости)
GameConfig.FriendsBonus = {
	PerFriend = 0.10,  -- +10% за каждого друга
	Max = 0.40,        -- не больше +40%
}

-- Офлайн-доход
GameConfig.Offline = {
	MaxSeconds = 2 * 24 * 60 * 60, -- максимум 2 дня
}

-- PvP
GameConfig.Combat = {
	HitCooldown = 1, -- перезарядка удара (секунды)
}

-- Ежедневные награды
GameConfig.Daily = {
	ResetHourUTC = 0, -- новый день начинается в 00:00 UTC
}

-- Участок: размеры временного участка и правила расстановки.
-- Слот — это вместимость участка, а не плитка на земле: яйцо можно поставить
-- в любом свободном месте внутри забора.
GameConfig.Plot = {
	TempCount = 12,                       -- сколько временных участков создать
	TempOrigin = Vector3.new(0, 5, -150), -- центр ряда временных участков (выше Baseplate)
	TempSpacing = 70,                     -- расстояние между временными участками
	TempFloorSize = Vector3.new(44, 1, 44), -- размер пола временного участка
	PlaceMargin = 3,                      -- насколько близко к забору можно ставить
	PlaceMinDistance = 6,                  -- минимальное расстояние между предметами
	PlaceCooldown = 0.25,                 -- защита от спама кнопкой "поставить"
	TickInterval = 1,                     -- как часто начислять доход и обновлять таймеры
}

-- Как выглядит забор на разных уровнях участка.
-- MinLevel — с какого уровня улучшения действует этот вид.
-- Если сделаешь свои модели заборов, эта таблица не используется (см. PlotBuilder).
GameConfig.Plot.FenceStyles = {
	{ MinLevel = 0,  Height = 3, Color = Color3.fromRGB(120, 85, 50),   Material = Enum.Material.WoodPlanks },
	{ MinLevel = 3,  Height = 4, Color = Color3.fromRGB(150, 155, 165), Material = Enum.Material.Metal },
	{ MinLevel = 7,  Height = 5, Color = Color3.fromRGB(225, 180, 60),  Material = Enum.Material.Metal },
	{ MinLevel = 12, Height = 6, Color = Color3.fromRGB(120, 230, 255), Material = Enum.Material.Neon },
}

-- Продажа мобов и яиц
GameConfig.Sell = {
	MobSeconds = 60, -- моб продаётся за свой доход за 60 секунд
	EggFactor = 0.5, -- яйцо стоит вдвое дешевле моба, который из него вылупится
	MinPrice = 1,
}

return GameConfig
