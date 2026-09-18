-- Items: мечи и трейлы. ВРЕМЕННЫЕ ЗНАЧЕНИЯ.

local Items = {}

-- Мечи выдаются за открытие всех мобов биома (см. Biomes.SwordReward)
-- Knockback — сила отталкивания другого игрока
Items.Swords = {
	WoodenSword = { DisplayName = "Wooden Sword", Knockback = 40, ModelName = "WoodenSword" },
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
