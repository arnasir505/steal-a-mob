-- DataTemplate: как выглядят сохранённые данные нового игрока.
-- Если позже добавить сюда новое поле, у старых игроков оно появится автоматически.
--
-- Моб или яйцо хранится так: { MobId = "Chicken", Weight = 1.5, Mutation = "None" }
-- (у яйца мутации нет — она выпадает при вылуплении)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

return {
	Version = 1,

	-- Экономика
	Money = 0,
	Speed = GameConfig.Speed.StartStat,
	TreadmillLevel = 0,
	BaseLevel = 0, -- слотов на базе = 1 + BaseLevel

	-- Рюкзак. Ключ — уникальный номер предмета строкой ("1", "2", ...)
	NextItemId = 1,
	Backpack = {
		Eggs = {},
		Mobs = {},
	},

	-- Участок. Ключ — номер слота строкой.
	-- Яйцо:  { Type = "Egg", Item = {...}, HatchEndsAt = <время> }
	-- Моб:   { Type = "Mob", Item = {...} }
	-- Время хранится как дата окончания, поэтому яйца вылупляются и пока игрок офлайн.
	Plot = {
		Slots = {},
	},

	-- Индекс: [MobId] = true
	Index = {},

	-- Мечи и трейлы: [Id] = true
	Swords = {},
	EquippedSword = "",
	Trails = {},
	EquippedTrail = "",

	-- Ежедневный календарь
	Daily = {
		SeasonId = "",
		Claimed = 0,        -- сколько наград уже забрано в этом сезоне
		LastClaimDay = -1,  -- номер дня последней награды
	},

	TutorialDone = false,

	-- Номера уже обработанных покупок за Robux (защита от двойной выдачи)
	ProcessedReceipts = {},

	-- Время последнего сохранения (для офлайн-дохода)
	LastOnline = 0,

	Stats = {
		TotalEarned = 0,
		EggsStolen = 0,
		JoinCount = 0,
	},
}
