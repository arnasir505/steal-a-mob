-- Mobs: все мобы игры. ВРЕМЕННЫЕ ЗНАЧЕНИЯ — заменим твоими.
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

local Mobs = {
	Chicken = { DisplayName = "Chicken", Biome = "Plains", BaseIncome = 1, SpawnWeight = 1, ModelName = "Chicken", EggModelName = "PlainsEgg" },
	Pig     = { DisplayName = "Pig",     Biome = "Plains", BaseIncome = 2, SpawnWeight = 1, ModelName = "Pig",     EggModelName = "PlainsEgg" },
	Sheep   = { DisplayName = "Sheep",   Biome = "Plains", BaseIncome = 3, SpawnWeight = 1, ModelName = "Sheep",   EggModelName = "PlainsEgg" },
	Cow     = { DisplayName = "Cow",     Biome = "Plains", BaseIncome = 5, SpawnWeight = 1, ModelName = "Cow",     EggModelName = "PlainsEgg" },
	Horse   = { DisplayName = "Horse",   Biome = "Plains", BaseIncome = 8, SpawnWeight = 1, ModelName = "Horse",   EggModelName = "PlainsEgg" },
}

return Mobs
