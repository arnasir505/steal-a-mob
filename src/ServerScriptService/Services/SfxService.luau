-- SfxService: звуки с сервера. Id и громкость — Config/Sounds.
--
--   SfxService.PlayAt(part, "SwordHit")     -- звук в мире: слышат все рядом
--   SfxService.Loop(part, "BossSnore")      -- повторяющийся звук в мире (вернёт Sound)
--   SfxService.PlayFor(player, "EggPickup") -- только этому игроку
--   SfxService.PlayForAll("RareEggSpawn")   -- всем игрокам сервера
--
-- Звуки у одного игрока (интерфейс, музыка, погоня, дорожка) включает сам клиент
-- (Sounds.client.luau). Пока у звука Id = 0, он просто не играет.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local SfxService = {}

-- Создаём сразу при загрузке модуля: другие сервисы могут звать PlayFor раньше Init
local playEvent = Remotes.Event("PlaySound")

local HEAR_DISTANCE = 90 -- на каком расстоянии звук в мире затихает совсем

local function makeSound(name, parent)
	local resolved = Sounds.Resolve(name)
	if not resolved or not parent then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = resolved.SoundId
	sound.Volume = resolved.Volume
	sound.PlaybackSpeed = resolved.Pitch
	sound.RollOffMaxDistance = HEAR_DISTANCE
	sound.RollOffMinDistance = 10
	sound.Parent = parent
	return sound
end

function SfxService.PlayAt(part, name)
	local sound = makeSound(name, part)
	if not sound then
		return
	end
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, 15) -- на случай, если звук не загрузился и Ended не придёт
end

function SfxService.Loop(part, name)
	local sound = makeSound(name, part)
	if sound then
		sound.Looped = true
	end
	return sound
end

function SfxService.PlayFor(player, name)
	if Sounds.Resolve(name) then
		playEvent:FireClient(player, name)
	end
end

function SfxService.PlayForAll(name)
	if Sounds.Resolve(name) then
		playEvent:FireAllClients(name)
	end
end

return SfxService
