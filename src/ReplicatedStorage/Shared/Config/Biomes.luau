-- Biomes: биомы по порядку от safe zone. ВРЕМЕННЫЕ ЗНАЧЕНИЯ.
--
-- Rarities       — какие редкости выпадают в этом биоме. Шансы берутся
--                  из Config/Rarities и делятся между ними по пропорции.
--                  Чем дальше биом, тем лучше должно быть окно редкостей.
-- Boss.Speed     — скорость босса в тех же единицах, что и стата игрока.
--                  Чтобы убежать, эффективная скорость игрока должна быть >= этого числа.
-- Boss.Knockback — сила отталкивания (дальше биом — сильнее)
-- SwordReward    — меч за открытие всех мобов биома в индексе
-- ModelName      — имя папки биома в Workspace (сделаешь сам)
--
-- Какие мобы живут в биоме, задаётся в Config/Mobs полем Biome.

local Biomes = {}

Biomes.List = {
	{
		Id = "Plains",
		DisplayName = "Plains",
		ModelName = "Plains",
		EggsAtOnce = 5,
		Rarities = { "Common", "Uncommon", "Rare" },
		SwordReward = "WoodenSword",
		Boss = {
			DisplayName = "Farmer",
			ModelName = "Farmer",
			Speed = 5,
			Knockback = 60,
		},
	},
	-- Следующие биомы добавляются сюда же, по порядку. Например:
	-- { Id = "Forest", Rarities = { "Uncommon", "Rare", "Epic" }, ... },
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
