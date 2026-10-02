-- Mobs: все мобы игры. ВРЕМЕННЫЕ ЗНАЧЕНИЯ — заменим твоими.
-- Мобы каждого следующего биома в ~4 раза доходнее предыдущего (BaseIncome).
-- Пока нет модели моба или яйца, игра строит временную из кубиков.
--
-- ВАЖНО: редкость принадлежит не мобу, а конкретному яйцу.
-- Одна и та же Курица бывает и Common, и Rare — от этого зависит её доход,
-- время вылупления и цвет. Какие редкости выпадают в биоме, решает Config/Biomes.
--
-- Biome        — в каком биоме спавнятся яйца этого моба
-- BaseIncome   — деньги в секунду при весе 1 кг, редкости Common и без мутации
-- SpawnWeight  — насколько часто выбирается именно этот моб внутри своего биома
--                (у всех 1 — значит поровну; поставь 2, чтобы попадался вдвое чаще)
-- ModelName    — имя модели моба в ReplicatedStorage.Assets.Mobs (сделаешь сам)
-- EggModelName — имя модели яйца в ReplicatedStorage.Assets.Eggs.
--                Если не указать, берётся ModelName. Одну модель яйца можно дать
--                нескольким мобам — тогда по виду яйца не понять, кто внутри.
-- Scale        — размер модели моба при весе 1 кг: 1 = как сделана в Studio,
--                0.5 = вдвое меньше, 2 = вдвое больше. Дальше модель растёт
--                с весом сама (GameConfig.Weight.MaxModelScale и ModelScaleCurve).
--                Можно и просто изменить модель инструментом Scale в Studio —
--                игра это учтёт.
-- EggScale     — то же самое для модели яйца.

local Mobs = {
	-- Plains
	Chicken = { DisplayName = "Chicken", Biome = "Plains", BaseIncome = 1, SpawnWeight = 1, ModelName = "Chicken", EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },
	Pig     = { DisplayName = "Pig",     Biome = "Plains", BaseIncome = 2, SpawnWeight = 1, ModelName = "Pig",     EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },
	Sheep   = { DisplayName = "Sheep",   Biome = "Plains", BaseIncome = 3, SpawnWeight = 1, ModelName = "Sheep",   EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },
	Cow     = { DisplayName = "Cow",     Biome = "Plains", BaseIncome = 5, SpawnWeight = 1, ModelName = "Cow",     EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },
	Horse   = { DisplayName = "Horse",   Biome = "Plains", BaseIncome = 8, SpawnWeight = 1, ModelName = "Horse",   EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },

	-- Forest
	Squirrel = { DisplayName = "Squirrel", Biome = "Forest", BaseIncome = 4, SpawnWeight = 1, ModelName = "Squirrel", EggModelName = "ForestEgg", Scale = 1, EggScale = 2.1 },
	Rabbit   = { DisplayName = "Rabbit", Biome = "Forest", BaseIncome = 7, SpawnWeight = 1, ModelName = "Rabbit", EggModelName = "ForestEgg", Scale = 1, EggScale = 2.1 },
	Fox      = { DisplayName = "Fox", Biome = "Forest", BaseIncome = 10, SpawnWeight = 1, ModelName = "Fox", EggModelName = "ForestEgg", Scale = 1, EggScale = 2.1 },
	Deer     = { DisplayName = "Deer", Biome = "Forest", BaseIncome = 15, SpawnWeight = 1, ModelName = "Deer", EggModelName = "ForestEgg", Scale = 1, EggScale = 2.1 },
	Bear     = { DisplayName = "Bear", Biome = "Forest", BaseIncome = 25, SpawnWeight = 1, ModelName = "Bear", EggModelName = "ForestEgg", Scale = 1, EggScale = 2.1 },

	-- Desert
	Lizard   = { DisplayName = "Lizard", Biome = "Desert", BaseIncome = 15, SpawnWeight = 1, ModelName = "Lizard", EggModelName = "DesertEgg", Scale = 1, EggScale = 2.1 },
	Scorpion = { DisplayName = "Scorpion", Biome = "Desert", BaseIncome = 25, SpawnWeight = 1, ModelName = "Scorpion", EggModelName = "DesertEgg", Scale = 1, EggScale = 2.1 },
	Fennec   = { DisplayName = "Fennec", Biome = "Desert", BaseIncome = 40, SpawnWeight = 1, ModelName = "Fennec", EggModelName = "DesertEgg", Scale = 1, EggScale = 2.1 },
	Vulture  = { DisplayName = "Vulture", Biome = "Desert", BaseIncome = 60, SpawnWeight = 1, ModelName = "Vulture", EggModelName = "DesertEgg", Scale = 1, EggScale = 2.1 },
	Camel    = { DisplayName = "Camel", Biome = "Desert", BaseIncome = 100, SpawnWeight = 1, ModelName = "Camel", EggModelName = "DesertEgg", Scale = 1, EggScale = 2.1 },

	-- Snow
	Penguin  = { DisplayName = "Penguin", Biome = "Snow", BaseIncome = 60, SpawnWeight = 1, ModelName = "Penguin", EggModelName = "SnowEgg", Scale = 1, EggScale = 2.1 },
	SnowOwl  = { DisplayName = "Snow Owl", Biome = "Snow", BaseIncome = 100, SpawnWeight = 1, ModelName = "SnowOwl", EggModelName = "SnowEgg", Scale = 1, EggScale = 2.1 },
	Seal     = { DisplayName = "Seal", Biome = "Snow", BaseIncome = 150, SpawnWeight = 1, ModelName = "Seal", EggModelName = "SnowEgg", Scale = 1, EggScale = 2.1 },
	Reindeer = { DisplayName = "Reindeer", Biome = "Snow", BaseIncome = 250, SpawnWeight = 1, ModelName = "Reindeer", EggModelName = "SnowEgg", Scale = 1, EggScale = 2.1 },
	Mammoth  = { DisplayName = "Mammoth", Biome = "Snow", BaseIncome = 400, SpawnWeight = 1, ModelName = "Mammoth", EggModelName = "SnowEgg", Scale = 1, EggScale = 2.1 },

	-- Swamp
	Frog       = { DisplayName = "Frog", Biome = "Swamp", BaseIncome = 250, SpawnWeight = 1, ModelName = "Frog", EggModelName = "SwampEgg", Scale = 1, EggScale = 2.1 },
	Newt       = { DisplayName = "Newt", Biome = "Swamp", BaseIncome = 400, SpawnWeight = 1, ModelName = "Newt", EggModelName = "SwampEgg", Scale = 1, EggScale = 2.1 },
	SnapTurtle = { DisplayName = "Snap Turtle", Biome = "Swamp", BaseIncome = 600, SpawnWeight = 1, ModelName = "SnapTurtle", EggModelName = "SwampEgg", Scale = 1, EggScale = 2.1 },
	Heron      = { DisplayName = "Heron", Biome = "Swamp", BaseIncome = 1000, SpawnWeight = 1, ModelName = "Heron", EggModelName = "SwampEgg", Scale = 1, EggScale = 2.1 },
	Crocodile  = { DisplayName = "Crocodile", Biome = "Swamp", BaseIncome = 1500, SpawnWeight = 1, ModelName = "Crocodile", EggModelName = "SwampEgg", Scale = 1, EggScale = 2.1 },

	-- Underworld
	EmberImp  = { DisplayName = "Ember Imp", Biome = "Underworld", BaseIncome = 1000, SpawnWeight = 1, ModelName = "EmberImp", EggModelName = "UnderworldEgg", Scale = 1, EggScale = 2.1 },
	MagmaSlug = { DisplayName = "Magma Slug", Biome = "Underworld", BaseIncome = 1500, SpawnWeight = 1, ModelName = "MagmaSlug", EggModelName = "UnderworldEgg", Scale = 1, EggScale = 2.1 },
	CinderBat = { DisplayName = "Cinder Bat", Biome = "Underworld", BaseIncome = 2500, SpawnWeight = 1, ModelName = "CinderBat", EggModelName = "UnderworldEgg", Scale = 1, EggScale = 2.1 },
	LavaHound = { DisplayName = "Lava Hound", Biome = "Underworld", BaseIncome = 4000, SpawnWeight = 1, ModelName = "LavaHound", EggModelName = "UnderworldEgg", Scale = 1, EggScale = 2.1 },
	FireDrake = { DisplayName = "Fire Drake", Biome = "Underworld", BaseIncome = 6000, SpawnWeight = 1, ModelName = "FireDrake", EggModelName = "UnderworldEgg", Scale = 1, EggScale = 2.1 },

	-- CrystalCave
	GlowBeetle  = { DisplayName = "Glow Beetle", Biome = "CrystalCave", BaseIncome = 4000, SpawnWeight = 1, ModelName = "GlowBeetle", EggModelName = "CrystalEgg", Scale = 1, EggScale = 2.1 },
	CrystalBat  = { DisplayName = "Crystal Bat", Biome = "CrystalCave", BaseIncome = 6000, SpawnWeight = 1, ModelName = "CrystalBat", EggModelName = "CrystalEgg", Scale = 1, EggScale = 2.1 },
	GemMole     = { DisplayName = "Gem Mole", Biome = "CrystalCave", BaseIncome = 10000, SpawnWeight = 1, ModelName = "GemMole", EggModelName = "CrystalEgg", Scale = 1, EggScale = 2.1 },
	GeodeTurtle = { DisplayName = "Geode Turtle", Biome = "CrystalCave", BaseIncome = 15000, SpawnWeight = 1, ModelName = "GeodeTurtle", EggModelName = "CrystalEgg", Scale = 1, EggScale = 2.1 },
	PrismDragon = { DisplayName = "Prism Dragon", Biome = "CrystalCave", BaseIncome = 25000, SpawnWeight = 1, ModelName = "PrismDragon", EggModelName = "CrystalEgg", Scale = 1, EggScale = 2.1 },
}

return Mobs
