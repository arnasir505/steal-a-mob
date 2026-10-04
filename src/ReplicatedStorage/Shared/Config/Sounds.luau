-- Sounds: звуки и музыка. Впиши Id звука (Audio) вместо 0.
-- Пока стоит 0, звук просто не играет — игра не сломается.
--
-- Где брать: в Studio Toolbox → вкладка Audio (Creator Store) — там тысячи
-- бесплатных звуков, которые Roblox разрешает использовать. Правый клик → Copy Asset ID.
-- Свои файлы (mp3/ogg) загружаются через Asset Manager, но у Roblox есть
-- месячный лимит загрузок аудио и проверка модерацией.
--
-- Volume — громкость от 0 до 1 (подгони, чтобы все звуки были примерно одинаково громкими).
-- Pitch    — высота тона (1 — как есть, 0.6 — ниже и «тяжелее», 1.3 — выше).
-- Fallback — какой звук взять, пока у этого Id = 0 (с этим Pitch и Volume).
--            Так у каждого босса уже свой голос, а свой Id можно вписать позже.
-- Id может быть и текстом "rbxasset://sounds/..." — встроенные звуки Roblox,
-- они есть в любой игре и не требуют загрузки.

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
	BossSwing       = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.7 }, -- босс замахивается
	BossStep        = { Id = "rbxasset://sounds/action_footsteps_plastic.mp3", Volume = 0.6 }, -- шаг босса
	BossStomp       = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.8 }, -- тяжёлый шаг

	-- Свои звуки каждого босса: Boss<ModelName><Что>.
	--   Wake — проснулся (рык),  Hit — удар/толчок,  Step — шаг на бегу,  Snore — храп.
	-- Пока Id = 0, играет Fallback с другим Pitch — у каждого босса уже свой голос.
	BossFarmerWake       = { Id = 0, Fallback = "BossWake", Pitch = 1.1, Volume = 0.8 },
	BossFarmerHit        = { Id = 0, Fallback = "BossSwing", Pitch = 1.1, Volume = 0.7 },
	BossFarmerStep       = { Id = 0, Fallback = "BossStep", Pitch = 0.9, Volume = 0.5 },
	BossFarmerSnore      = { Id = 0, Fallback = "BossSnore", Pitch = 1.05, Volume = 0.5 },

	BossLumberjackWake   = { Id = 0, Fallback = "BossWake", Pitch = 0.9, Volume = 0.85 },
	BossLumberjackHit    = { Id = 0, Fallback = "BossSwing", Pitch = 0.8, Volume = 0.8 },
	BossLumberjackStep   = { Id = 0, Fallback = "BossStep", Pitch = 0.75, Volume = 0.6 },
	BossLumberjackSnore  = { Id = 0, Fallback = "BossSnore", Pitch = 0.85, Volume = 0.55 },

	BossPharaohWake      = { Id = 0, Fallback = "BossWake", Pitch = 0.75, Volume = 0.85 },
	BossPharaohHit       = { Id = 0, Fallback = "BossSwing", Pitch = 0.65, Volume = 0.8 },
	BossPharaohStep      = { Id = 0, Fallback = "BossStep", Pitch = 1.2, Volume = 0.45 },
	BossPharaohSnore     = { Id = 0, Fallback = "BossSnore", Pitch = 0.7, Volume = 0.5 },

	BossYetiWake         = { Id = 0, Fallback = "BossWake", Pitch = 0.55, Volume = 0.95 },
	BossYetiHit          = { Id = 0, Fallback = "BossStomp", Pitch = 0.6, Volume = 0.9 },
	BossYetiStep         = { Id = 0, Fallback = "BossStomp", Pitch = 0.7, Volume = 0.6 },
	BossYetiSnore        = { Id = 0, Fallback = "BossSnore", Pitch = 0.6, Volume = 0.6 },

	BossBogHermitWake    = { Id = 0, Fallback = "BossWake", Pitch = 1.35, Volume = 0.8 },
	BossBogHermitHit     = { Id = 0, Fallback = "BossSwing", Pitch = 1.3, Volume = 0.7 },
	BossBogHermitStep    = { Id = 0, Fallback = "BossStep", Pitch = 0.6, Volume = 0.5 },
	BossBogHermitSnore   = { Id = 0, Fallback = "BossSnore", Pitch = 1.3, Volume = 0.5 },

	BossInfernoKingWake  = { Id = 0, Fallback = "BossWake", Pitch = 0.45, Volume = 1 },
	BossInfernoKingHit   = { Id = 0, Fallback = "BossStomp", Pitch = 0.45, Volume = 1 },
	BossInfernoKingStep  = { Id = 0, Fallback = "BossStomp", Pitch = 0.55, Volume = 0.6 },
	BossInfernoKingSnore = { Id = 0, Fallback = "BossSnore", Pitch = 0.5, Volume = 0.6 },

	BossGemWardenWake    = { Id = 0, Fallback = "BossWake", Pitch = 0.65, Volume = 1 },
	BossGemWardenHit     = { Id = 0, Fallback = "BossStomp", Pitch = 0.4, Volume = 1 },
	BossGemWardenStep    = { Id = 0, Fallback = "BossStomp", Pitch = 0.4, Volume = 0.7 },
	BossGemWardenSnore   = { Id = 0, Fallback = "BossSnore", Pitch = 0.45, Volume = 0.6 },

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

-- Что играть для звука name: { SoundId, Volume, Pitch } или nil (звука нет).
-- Пока у звука Id = 0, берётся его Fallback — с Pitch и Volume этого звука.
function Sounds.Resolve(name)
	local config = Sounds.List[name]
	if not config then
		return nil
	end
	local id = config.Id
	if type(id) == "string" and id ~= "" then
		return { SoundId = id, Volume = config.Volume or 0.5, Pitch = config.Pitch or 1 }
	end
	if type(id) == "number" and id > 0 then
		-- %d: длинное число через tostring может стать "1.3e+14"
		return { SoundId = "rbxassetid://" .. string.format("%d", id), Volume = config.Volume or 0.5, Pitch = config.Pitch or 1 }
	end
	if config.Fallback and config.Fallback ~= name then
		local base = Sounds.Resolve(config.Fallback)
		if base then
			base.Volume = config.Volume or base.Volume
			base.Pitch = (config.Pitch or 1) * base.Pitch
		end
		return base
	end
	return nil
end

-- Свой звук босса (BossFarmerWake) или общий (BossWake), если своего нет в списке
function Sounds.BossKey(modelName, what)
	local own = "Boss" .. tostring(modelName) .. what
	if Sounds.List[own] then
		return own
	end
	return "Boss" .. what
end

return Sounds
