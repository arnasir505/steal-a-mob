-- Biomes: биомы по порядку от safe zone. ВРЕМЕННЫЕ ЗНАЧЕНИЯ.
-- Boss.Speed     — скорость босса в тех же единицах, что и стата игрока.
--                  Чтобы убежать, эффективная скорость игрока должна быть >= этого числа.
-- Boss.Knockback — сила отталкивания (дальше биом — сильнее)
-- SwordReward    — меч за открытие всех мобов биома в индексе
-- ModelName      — имя папки биома в Workspace (сделаешь сам)

local Biomes = {}

Biomes.List = {
	{
		Id = "Plains",
		DisplayName = "Plains",
		ModelName = "Plains",
		EggsAtOnce = 5,
		SwordReward = "WoodenSword",
		Boss = {
			DisplayName = "Plains Guardian",
			ModelName = "PlainsBoss",
			Speed = 5,
			Knockback = 60,
		},
	},
	-- Следующие биомы добавляются сюда же, по порядку:
	-- { Id = "Forest", ... },
}

-- Быстрый поиск биома по Id
local byId = {}
for index, biome in ipairs(Biomes.List) do
	biome.Order = index
	byId[biome.Id] = biome
end

function Biomes.Get(biomeId)
	return byId[biomeId]
end

return Biomes
