-- Sounds: звуки и музыка. Впиши Id звука (Audio) вместо 0.
-- Пока стоит 0, звук просто не играет — игра не сломается.
--
-- Где брать: в Studio Toolbox → вкладка Audio (Creator Store) — там тысячи
-- бесплатных звуков, которые Roblox разрешает использовать. Правый клик → Copy Asset ID.
-- Свои файлы (mp3/ogg) загружаются через Asset Manager, но у Roblox есть
-- месячный лимит загрузок аудио и проверка модерацией.
--
-- Volume — громкость от 0 до 1 (подгони, чтобы все звуки были примерно одинаково громкими).
-- Сами звуки к событиям игры подключаются в коде — это следующий шаг.

local Sounds = {}

Sounds.List = {
	-- Интерфейс
	UiClick         = { Id = 535716488, Volume = 0.5 }, -- нажатие кнопки
	UiOpen          = { Id = 127877437691780, Volume = 0.5 }, -- открылось окно
	UiClose         = { Id = 8968249849, Volume = 0.4 }, -- закрылось окно
	PurchaseSuccess = { Id = 85494326384043, Volume = 0.6 }, -- покупка/улучшение за деньги
	PurchaseFail    = { Id = 89595839127625, Volume = 0.5 }, -- не хватает денег
	Notify          = { Id = 83547933303850, Volume = 0.4 }, -- всплыло сообщение

	-- Яйца
	EggPickup       = { Id = 90752223133261, Volume = 0.6 }, -- поднял яйцо
	EggDrop         = { Id = 139192037637046, Volume = 0.6 }, -- бросил / выбили яйцо
	EggPlace        = { Id = 135549838877133, Volume = 0.5 }, -- поставил на участок
	EggSecured      = { Id = 135724514015482, Volume = 0.7 }, -- донёс до safe zone
	EggHatch        = { Id = 110476620796113, Volume = 0.7 }, -- яйцо вылупилось
	RareHatch       = { Id = 114508418833350, Volume = 0.8 }, -- редкая мутация (Diamond, Rainbow)
	RareEggSpawn    = { Id = 72777660773179, Volume = 0.7 }, -- объявление о редком яйце

	-- Босс и погоня
	BossWake        = { Id = 135439749484858, Volume = 0.8 }, -- босс проснулся
	BossSnore       = { Id = 135148954440171, Volume = 0.5 }, -- босс спит (повторяется, слышно рядом с ним)
	Caught          = { Id = 138637983416785, Volume = 0.8 }, -- босс поймал / толкнул
	ChaseMusic      = { Id = 86217880846250, Volume = 0.5 }, -- тревожная музыка, пока за тобой гонятся

	-- Бой
	SwordSwing      = { Id = 140527314975641, Volume = 0.6 }, -- взмах меча
	SwordHit        = { Id = 103315511081890, Volume = 0.7 }, -- попал мечом

	-- Участок и прогресс
	Upgrade         = { Id = 0, Volume = 0.7 }, -- улучшил базу или дорожку
	TreadmillRun    = { Id = 79250663775359, Volume = 0.3 }, -- бег по дорожке (повторяется)
	Fuse            = { Id = 0, Volume = 0.7 }, -- синтез мобов
	IndexUnlock     = { Id = 0, Volume = 0.7 }, -- новый моб в индексе
	DailyReward     = { Id = 0, Volume = 0.7 }, -- награда календаря

	-- Раунды
	RoundWarning    = { Id = 101969970998775, Volume = 0.6 }, -- 10 секунд до конца раунда
	RoundStart      = { Id = 117166473587029, Volume = 0.6 }, -- новые яйца, биомы открыты

	-- Музыка (повторяется)
	MusicLobby      = { Id = 119504467986585, Volume = 0.1 }, -- в safe zone и на участке
	MusicPlains     = { Id = 0, Volume = 0.3 }, -- в биоме Plains
	MusicForest     = { Id = 0, Volume = 0.3 },
	MusicDesert     = { Id = 0, Volume = 0.3 },
	MusicSnow       = { Id = 0, Volume = 0.3 },
	MusicSwamp      = { Id = 0, Volume = 0.3 },
	MusicUnderworld = { Id = 0, Volume = 0.3 },
	MusicCrystalCave = { Id = 0, Volume = 0.3 },
}

return Sounds
