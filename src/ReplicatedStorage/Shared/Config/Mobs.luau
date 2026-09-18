-- Mobs: все мобы игры. ВРЕМЕННЫЕ ЗНАЧЕНИЯ — заменим твоими.
-- Каждое яйцо — это яйцо конкретного моба: из яйца курицы вылупляется курица.
-- Biome        — в каком биоме спавнится яйцо
-- Rarity       — редкость (из Rarities)
-- BaseIncome   — деньги в секунду при весе 1 кг, без мутации
-- ModelName    — имя модели моба в ReplicatedStorage.Assets.Mobs (сделаешь сам)
-- EggModelName — имя модели яйца в ReplicatedStorage.Assets.Eggs.
--                Если не указать, берётся ModelName. Можно дать нескольким мобам
--                одну модель яйца — тогда по виду яйца не понять, кто внутри.

local Mobs = {
	Chicken = { DisplayName = "Chicken", Biome = "Plains", Rarity = "Common",    BaseIncome = 1,  ModelName = "Chicken", EggModelName = "PlainsEgg" },
	Pig     = { DisplayName = "Pig",     Biome = "Plains", Rarity = "Uncommon",  BaseIncome = 2,  ModelName = "Pig",     EggModelName = "PlainsEgg" },
	Sheep   = { DisplayName = "Sheep",   Biome = "Plains", Rarity = "Rare",      BaseIncome = 3,  ModelName = "Sheep",   EggModelName = "PlainsEgg" },
	Cow     = { DisplayName = "Cow",     Biome = "Plains", Rarity = "Epic",      BaseIncome = 5,  ModelName = "Cow",     EggModelName = "PlainsEgg" },
	Horse   = { DisplayName = "Horse",   Biome = "Plains", Rarity = "Legendary", BaseIncome = 8,  ModelName = "Horse",   EggModelName = "PlainsEgg" },
}

return Mobs
