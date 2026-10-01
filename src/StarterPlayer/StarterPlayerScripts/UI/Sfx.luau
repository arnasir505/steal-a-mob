-- Sfx: звуки на клиенте (только для этого игрока). Id и громкость — Config/Sounds.
--
--   Sfx.Play("UiClick")             -- проиграть один раз
--   Sfx.SetLoop("TreadmillRun", on) -- включить / выключить повторяющийся звук
--   Sfx.Fade("MusicLobby", 0.3, 1)  -- плавно изменить громкость (музыка)
--   Sfx.RecentlyPlayed(0.4)         -- играл ли звук только что (чтобы не накладывать)
-- Пока у звука Id = 0, он просто не играет.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local Sfx = {}

local folder = Instance.new("Folder")
folder.Name = "GameSounds"
folder.Parent = SoundService

local cache = {} -- [name] = Sound
local lastPlayed = 0

local function get(name)
	if cache[name] ~= nil then
		return cache[name] or nil
	end
	local config = Sounds.List[name]
	if not config or config.Id == 0 then
		cache[name] = false
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. config.Id
	sound.Volume = config.Volume or 0.5
	sound.Parent = folder
	cache[name] = sound
	return sound
end

-- Обычная громкость звука из конфига
function Sfx.Volume(name)
	local config = Sounds.List[name]
	return config and config.Volume or 0.5
end

function Sfx.Play(name)
	local sound = get(name)
	if not sound then
		return
	end
	sound.TimePosition = 0
	sound:Play()
	lastPlayed = os.clock()
end

function Sfx.SetLoop(name, on)
	local sound = get(name)
	if not sound then
		return nil
	end
	sound.Looped = true
	if on and not sound.IsPlaying then
		sound:Play()
	elseif not on and sound.IsPlaying then
		sound:Stop()
	end
	return sound
end

-- Плавно довести громкость до volume за seconds секунд; 0 — остановить в конце
function Sfx.Fade(name, volume, seconds)
	local sound = get(name)
	if not sound then
		return
	end
	if volume > 0 and not sound.IsPlaying then
		sound.Looped = true
		sound.Volume = 0
		sound:Play()
	end
	local tween = TweenService:Create(sound, TweenInfo.new(seconds or 1), { Volume = volume })
	tween:Play()
	if volume <= 0 then
		tween.Completed:Connect(function()
			if sound.Volume <= 0.001 then
				sound:Stop()
			end
		end)
	end
end

function Sfx.RecentlyPlayed(seconds)
	return os.clock() - lastPlayed < seconds
end

-- Заранее загружаем все звуки, чтобы первый раз не было задержки,
-- и пишем в Output, какие не загрузились (чужой закрытый звук, неверный Id)
task.spawn(function()
	local list, names = {}, {}
	for name in pairs(Sounds.List) do
		local sound = get(name)
		if sound then
			table.insert(list, sound)
			names[sound.SoundId] = name
		end
	end
	local failed = {}
	pcall(ContentProvider.PreloadAsync, ContentProvider, list, function(assetId, status)
		if status ~= Enum.AssetFetchStatus.Success then
			table.insert(failed, (names[assetId] or assetId) .. " (" .. status.Name .. ")")
		end
	end)
	print(string.format("[Sfx] Звуков загружено: %d из %d", #list - #failed, #list))
	if #failed > 0 then
		warn("[Sfx] Не загрузились: " .. table.concat(failed, ", "))
	end
end)

return Sfx
