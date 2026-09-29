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
-- Scale        — размер модели моба при весе 1 кг: 1 = как сделана в Studio,
--                0.5 = вдвое меньше, 2 = вдвое больше. Дальше модель растёт
--                с весом сама (GameConfig.Weight.MaxModelScale и ModelScaleCurve).
--                Можно и просто изменить модель инструментом Scale в Studio —
--                игра это учтёт.
-- EggScale     — то же самое для модели яйца.

local Mobs = {
	Chicken = { DisplayName = "Chicken", Biome = "Plains", BaseIncome = 1, SpawnWeight = 1, ModelName = "Chicken", EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },
	Pig     = { DisplayName = "Pig",     Biome = "Plains", BaseIncome = 2, SpawnWeight = 1, ModelName = "Pig",     EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },
	Sheep   = { DisplayName = "Sheep",   Biome = "Plains", BaseIncome = 3, SpawnWeight = 1, ModelName = "Sheep",   EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },
	Cow     = { DisplayName = "Cow",     Biome = "Plains", BaseIncome = 5, SpawnWeight = 1, ModelName = "Cow",     EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },
	Horse   = { DisplayName = "Horse",   Biome = "Plains", BaseIncome = 8, SpawnWeight = 1, ModelName = "Horse",   EggModelName = "PlainsEgg", Scale = 1, EggScale = 2.1 },
}

return Mobs
