-- Seasons: сезоны и календарь ежедневных наград.
-- Каждый день входа открывает СЛЕДУЮЩУЮ награду (пропуск дня прогресс не сбрасывает).
-- За один день можно забрать только одну награду.
-- Когда сезон заканчивается, незабранные награды сгорают, начинается новый календарь.
--
-- Типы наград:
--   { Type = "Money", Amount = 1000 }
--   { Type = "Speed", Amount = 500 }
--   { Type = "Egg",   MobId = "Cow", Weight = 5 }
--   { Type = "Trail", TrailId = "Season1Trail" }

local Seasons = {}

Seasons.DaysInCalendar = 30

-- Дата в UTC -> число секунд (так время одинаковое на всех серверах)
local function utc(year, month, day)
	return DateTime.fromUniversalTime(year, month, day, 0, 0, 0).UnixTimestamp
end

Seasons.List = {
	{
		Id = "S1",
		DisplayName = "Season 1",
		StartsAt = utc(2026, 10, 1),
		EndsAt = utc(2026, 11, 5), -- 35 дней: 30 наград + 5 дней запаса
		Rewards = {
			[1]  = { Type = "Money", Amount = 500 },
			[2]  = { Type = "Speed", Amount = 50 },
			[3]  = { Type = "Egg", MobId = "Pig", Weight = 2 },
			[7]  = { Type = "Egg", MobId = "Cow", Weight = 5 },
			[14] = { Type = "Egg", MobId = "Horse", Weight = 3 },
			[30] = { Type = "Trail", TrailId = "Season1Trail" }, -- эксклюзивная награда сезона
		},
	},
}

-- ВРЕМЕННО: заполняем пустые дни деньгами, пока ты не расписал все 30 наград
for _, season in ipairs(Seasons.List) do
	for day = 1, Seasons.DaysInCalendar do
		if season.Rewards[day] == nil then
			season.Rewards[day] = { Type = "Money", Amount = 500 * day }
		end
	end
end

-- Текущий сезон (или nil, если сейчас перерыв между сезонами)
function Seasons.GetActive(now)
	now = now or os.time()
	for _, season in ipairs(Seasons.List) do
		if now >= season.StartsAt and now < season.EndsAt then
			return season
		end
	end
	return nil
end

return Seasons
