-- Items: мечи и трейлы. ВРЕМЕННЫЕ ЗНАЧЕНИЯ.

local Items = {}

-- Мечи выдаются за открытие всех мобов биома (см. Biomes.SwordReward).
-- В руках всегда один меч; новый меч сильнее надетого надевается сам.
-- Knockback — сила толчка: скорость в студах в секунду (у босса Plains — 60).
--             Чем реже меч, тем она больше.
-- Rarity    — редкость меча (цвет в интерфейсе, у временной модели — цвет лезвия)
-- Color     — необязательно: цвет лезвия временной модели
-- ModelName — модель в ReplicatedStorage.Assets.Swords (Tool или модель с деталью Handle).
--             Нет модели — выдаётся временный меч из кубиков.
Items.Swords = {
	WoodenSword = { DisplayName = "Wooden Sword", Rarity = "Common", Knockback = 40, ModelName = "WoodenSword",
		Color = Color3.fromRGB(170, 125, 75) },
		DiamondSword = { DisplayName = "Diamond Sword", Rarity = "Legendary", Knockback = 114, ModelName = "DiamondSword",
		Color = Color3.fromRGB(170, 125, 75) },
}

-- Трейлы покупаются за деньги и дают множитель к беговой дорожке.
-- Надет может быть только один трейл.
-- Price = 0 и Seasonal = true — трейл нельзя купить, только получить в календаре.
Items.Trails = {
	BlueTrail    = { DisplayName = "Blue Trail",     Price = 1000,   TreadmillMult = 1.1, Color = Color3.fromRGB(70, 140, 255) },
	GreenTrail   = { DisplayName = "Green Trail",    Price = 25000,  TreadmillMult = 1.25, Color = Color3.fromRGB(90, 220, 90) },
	FireTrail    = { DisplayName = "Fire Trail",     Price = 500000, TreadmillMult = 1.5, Color = Color3.fromRGB(255, 120, 30) },
	Season1Trail = { DisplayName = "Season 1 Trail", Price = 0, Seasonal = true, TreadmillMult = 1.75, Color = Color3.fromRGB(255, 215, 0) },
}

return Items
