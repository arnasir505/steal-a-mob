-- Rarities: редкости мобов и яиц. ВРЕМЕННЫЕ ЗНАЧЕНИЯ — заменим твоими.
-- IncomeMult  — множитель дохода
-- HatchTime   — базовое время вылупления (секунды) для яйца весом 1 кг
-- SpawnWeight — насколько часто спавнится (чем больше, тем чаще)
-- Announce    — показывать ли всем игрокам сообщение, когда такое яйцо появилось

local Rarities = {}

-- Порядок от самой обычной к самой редкой (важно для погони босса)
Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

Rarities.Data = {
	Common    = { DisplayName = "Common",    Color = Color3.fromRGB(200, 200, 200), IncomeMult = 1,    HatchTime = 30,    SpawnWeight = 600, Announce = false },
	Uncommon  = { DisplayName = "Uncommon",  Color = Color3.fromRGB(90, 200, 90),   IncomeMult = 3,    HatchTime = 60,    SpawnWeight = 250, Announce = false },
	Rare      = { DisplayName = "Rare",      Color = Color3.fromRGB(70, 140, 255),  IncomeMult = 10,   HatchTime = 180,   SpawnWeight = 100, Announce = false },
	Epic      = { DisplayName = "Epic",      Color = Color3.fromRGB(170, 80, 255),  IncomeMult = 40,   HatchTime = 600,   SpawnWeight = 35,  Announce = false },
	Legendary = { DisplayName = "Legendary", Color = Color3.fromRGB(255, 180, 40),  IncomeMult = 150,  HatchTime = 1800,  SpawnWeight = 10,  Announce = true },
	Mythic    = { DisplayName = "Mythic",    Color = Color3.fromRGB(255, 60, 120),  IncomeMult = 600,  HatchTime = 3600,  SpawnWeight = 4,   Announce = true },
	Secret    = { DisplayName = "Secret",    Color = Color3.fromRGB(20, 20, 20),    IncomeMult = 3000, HatchTime = 10800, SpawnWeight = 1,   Announce = true },
}

-- Номер редкости (1 = Common). Нужен, чтобы сравнивать, какое яйцо реже.
local rank = {}
for i, id in ipairs(Rarities.Order) do
	rank[id] = i
end

function Rarities.GetRank(rarityId)
	return rank[rarityId] or 0
end

return Rarities
