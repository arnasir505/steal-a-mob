-- Rarities: редкости мобов и яиц.
--
-- SpawnWeight — шанс появления В ПРОЦЕНТАХ. Сумма всех = 100, поэтому число
--               и есть процент. Если сумма перестанет быть 100 (добавишь редкость
--               или поменяешь число), игра не сломается: шансы посчитаются
--               по пропорции. Но пока сумма = 100, читать таблицу проще.
-- IncomeMult  — множитель дохода
-- HatchTime   — базовое время вылупления (секунды) для яйца весом 1 кг
-- Announce    — показывать ли всем игрокам сообщение, когда такое яйцо появилось
--
-- Важно: редкость принадлежит яйцу, а не мобу. Одна и та же Курица бывает
-- Common и Rare. Какие редкости выпадают в биоме — список Rarities в Config/Biomes.
-- Если в Plains разрешены только Common, Uncommon и Rare, их шансы (50, 30, 10)
-- делятся между собой по пропорции: 55.6%, 33.3% и 11.1%.

local Rarities = {}

-- Порядок от самой обычной к самой редкой.
-- Важен для погони босса: босс гонится за самым редким яйцом.
Rarities.Order = {
	"Common", "Uncommon", "Rare", "Epic", "Legendary",
	"Mythic", "Galactic", "Ultra", "Abyssal", "Immortal",
}

Rarities.Data = {
	Common    = { DisplayName = "Common",    Color = Color3.fromRGB(165, 170, 175), SpawnWeight = 50,   IncomeMult = 1,    HatchTime = 30,    Announce = false },
	Uncommon  = { DisplayName = "Uncommon",  Color = Color3.fromRGB(80, 210, 90),   SpawnWeight = 30,   IncomeMult = 3,    HatchTime = 60,    Announce = false },
	Rare      = { DisplayName = "Rare",      Color = Color3.fromRGB(60, 140, 255),  SpawnWeight = 10,   IncomeMult = 10,   HatchTime = 150,   Announce = false },
	Epic      = { DisplayName = "Epic",      Color = Color3.fromRGB(170, 70, 255),  SpawnWeight = 5,    IncomeMult = 25,   HatchTime = 300,   Announce = false },
	Legendary = { DisplayName = "Legendary", Color = Color3.fromRGB(255, 175, 30),  SpawnWeight = 3,    IncomeMult = 60,   HatchTime = 600,   Announce = false },
	Mythic    = { DisplayName = "Mythic",    Color = Color3.fromRGB(255, 60, 120),  SpawnWeight = 1,    IncomeMult = 200,  HatchTime = 1200,  Announce = true },
	Galactic  = { DisplayName = "Galactic",  Color = Color3.fromRGB(0, 230, 220),   SpawnWeight = 0.5,  IncomeMult = 500,  HatchTime = 2400,  Announce = true },
	Ultra     = { DisplayName = "Ultra",     Color = Color3.fromRGB(255, 80, 0),    SpawnWeight = 0.3,  IncomeMult = 1200, HatchTime = 4200,  Announce = true },
	Abyssal   = { DisplayName = "Abyssal",   Color = Color3.fromRGB(35, 25, 75),    SpawnWeight = 0.15, IncomeMult = 3000, HatchTime = 7200,  Announce = true },
	Immortal  = { DisplayName = "Immortal",  Color = Color3.fromRGB(255, 255, 255), SpawnWeight = 0.05, IncomeMult = 8000, HatchTime = 14400, Announce = true },
}

-- Номер редкости (1 = Common). Нужен, чтобы сравнивать, какое яйцо реже.
local rank = {}
local totalWeight = 0
for i, id in ipairs(Rarities.Order) do
	rank[id] = i
	totalWeight = totalWeight + (Rarities.Data[id] and Rarities.Data[id].SpawnWeight or 0)
end

function Rarities.GetRank(rarityId)
	return rank[rarityId] or 0
end

-- Данные редкости. Если редкость незнакомая или её нет (старое сохранение),
-- считаем предмет самым обычным — игра не сломается.
function Rarities.Get(rarityId)
	return Rarities.Data[rarityId] or Rarities.Data[Rarities.Order[1]]
end

-- Настоящий шанс долей от 1 (0.005 = 0.5%). Для интерфейса и проверки баланса.
function Rarities.SpawnChance(rarityId)
	local data = Rarities.Data[rarityId]
	if not data or totalWeight <= 0 then
		return 0
	end
	return data.SpawnWeight / totalWeight
end

return Rarities
