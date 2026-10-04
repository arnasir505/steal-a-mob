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
--                  Это же число написано на табличке у босса ("Recommended").
-- Boss.Knockback — сила отталкивания: скорость полёта в студах в секунду
--                  (дальше биом — сильнее). 80 — ~40 студов, 1200 — ~2900 студов.
--                  Высота и торможение — GameConfig.Knockback
-- Boss.ModelName — имя модели босса. Положи её прямо в модель биома
--                  (Workspace.Biomes.Plains.Farmer) — где стоит, там и спит.
--                  Подробнее — в начале BossService.
-- Boss.TurnDegrees — если босс бежит боком или спиной, поставь 90, -90 или 180
-- SwordReward    — необязательно: меч за открытие всех мобов биома в индексе.
--                  У Plains награды нет: деревянный меч — начальный
--                  (GameConfig.Combat.StarterSword)
-- ModelName      — имя модели биома в Workspace.Biomes (сделаешь сам).
--                  Пока модели нет, биом просто не работает: игра пишет
--                  предупреждение в Output, остальные биомы работают.
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
		Boss = {
			DisplayName = "Farmer",
			ModelName = "Farmer",
			Speed = 1000,
			Knockback = 80,
			TurnDegrees = 0,
		},
	},
	{
		Id = "Forest",
		DisplayName = "Forest",
		ModelName = "Forest",
		EggsAtOnce = 5,
		Rarities = { "Uncommon", "Rare", "Epic" },
		MaxWeight = 5000,
		SwordReward = "VineBlade",
		Boss = {
			DisplayName = "Lumberjack",
			ModelName = "Lumberjack",
			Speed = 50000,
			Knockback = 150,
			TurnDegrees = 0,
		},
	},
	{
		Id = "Desert",
		DisplayName = "Desert",
		ModelName = "Desert",
		EggsAtOnce = 5,
		Rarities = { "Rare", "Epic", "Legendary" },
		MaxWeight = 50000,
		SwordReward = "SandSaber",
		Boss = {
			DisplayName = "Pharaoh",
			ModelName = "Pharaoh",
			Speed = 200000,
			Knockback = 250,
			TurnDegrees = 0,
		},
	},
	{
		Id = "Snow",
		DisplayName = "Snow",
		ModelName = "Snow",
		EggsAtOnce = 5,
		Rarities = { "Epic", "Legendary", "Mythic" },
		MaxWeight = 500000,
		SwordReward = "FrostBlade",
		Boss = {
			DisplayName = "Yeti",
			ModelName = "Yeti",
			Speed = 1000000,
			Knockback = 400,
			TurnDegrees = 0,
		},
	},
	{
		Id = "Swamp",
		DisplayName = "Swamp",
		ModelName = "Swamp",
		EggsAtOnce = 5,
		Rarities = { "Legendary", "Mythic", "Galactic" },
		MaxWeight = 5000000,
		SwordReward = "BogCleaver",
		Boss = {
			DisplayName = "Bog Hermit",
			ModelName = "BogHermit",
			Speed = 10000000,
			Knockback = 600,
			TurnDegrees = 0,
		},
	},
	{
		Id = "Underworld",
		DisplayName = "Underworld",
		ModelName = "Underworld",
		EggsAtOnce = 5,
		Rarities = { "Mythic", "Galactic", "Ultra" },
		MaxWeight = 25000000,
		SwordReward = "MagmaSword",
		Boss = {
			DisplayName = "Inferno King",
			ModelName = "InfernoKing",
			Speed = 100000000,
			Knockback = 850,
			TurnDegrees = 0,
		},
	},
	{
		Id = "CrystalCave",
		DisplayName = "Crystal Cave",
		ModelName = "CrystalCave",
		EggsAtOnce = 5,
		-- Последний биом: окно шире, только здесь выпадает Immortal
		Rarities = { "Galactic", "Ultra", "Abyssal", "Immortal" },
		MaxWeight = 100000000,
		SwordReward = "PrismSword",
		Boss = {
			DisplayName = "Gem Warden",
			ModelName = "GemWarden",
			Speed = 500000000,
			Knockback = 1200,
			TurnDegrees = 0,
		},
	},
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
