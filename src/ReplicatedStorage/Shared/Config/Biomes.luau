-- Biomes: биомы по порядку от safe zone. ВРЕМЕННЫЕ ЗНАЧЕНИЯ.
--
-- Rarities       — какие редкости выпадают в этом биоме. Шансы берутся
--                  из Config/Rarities и делятся между ними по пропорции.
--                  Чем дальше биом, тем лучше должно быть окно редкостей.
-- MaxWeight      — самое тяжёлое яйцо, которое может появиться в этом биоме (кг).
--                  Лёгкие яйца всё равно выпадают часто, тяжёлые — редко
--                  (насколько редко — GameConfig.Weight.SpawnRollPower).
--                  Чем дальше биом, тем больше можно ставить. Если не указать,
--                  берётся GameConfig.Weight.SpawnMaxWeight.
-- Boss.Speed     — скорость босса в тех же единицах, что и стата игрока.
--                  Чтобы убежать, эффективная скорость игрока должна быть >= этого числа.
-- Boss.Knockback — сила отталкивания: скорость толчка в студах в секунду
--                  (дальше биом — сильнее). Длительность толчка — GameConfig.Knockback
-- Boss.ModelName — имя модели босса. Положи её прямо в модель биома
--                  (Workspace.Biomes.Plains.Farmer) — где стоит, там и спит.
--                  Подробнее — в начале BossService.
-- Boss.TurnDegrees — если босс бежит боком или спиной, поставь 90, -90 или 180
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
		MaxWeight = 500,
		SwordReward = "WoodenSword",
		Boss = {
			DisplayName = "Farmer",
			ModelName = "Farmer",
			Speed = 5,
			Knockback = 60,
			TurnDegrees = 0,
		},
	},
	-- Следующие биомы добавляются сюда же, по порядку. Например:
	-- { Id = "Forest", Rarities = { "Uncommon", "Rare", "Epic" }, MaxWeight = 1000000, ... },
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
