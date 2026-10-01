-- GameSounds: звуки, которые клиент включает сам.
--  * сервер просит проиграть звук (SfxService.PlayFor / PlayForAll);
--  * сообщения на экране — тихий "дзынь" (если только что не играл другой звук);
--  * новый моб в индексе;
--  * музыка: в safe zone — MusicLobby, в биоме — Music<Id биома> (например MusicPlains),
--    если её нет — тоже MusicLobby. Где игрок — атрибут Zone от сервера (WorldService);
--  * погоня (атрибут ChasedBy): музыка затихает, играет ChaseMusic;
--  * бег по дорожке (атрибут OnTreadmill): повторяется TreadmillRun.
-- Звуки интерфейса (клик, окна) включает сам Kit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local Sfx = require(script.Parent:WaitForChild("UI"):WaitForChild("Sfx"))

local player = Players.LocalPlayer

Remotes.Event("PlaySound").OnClientEvent:Connect(function(name)
	Sfx.Play(name)
end)

-- Сообщение: "дзынь", но не поверх звука события (поднял яйцо, покупка...)
Remotes.Event("Notify").OnClientEvent:Connect(function()
	task.wait(0.05) -- звук события приходит тем же кадром — дадим ему сыграть первым
	if not Sfx.RecentlyPlayed(0.4) then
		Sfx.Play("Notify")
	end
end)

Remotes.Event("IndexUpdated").OnClientEvent:Connect(function()
	Sfx.Play("IndexUnlock")
end)

---------------------------------------------------------------------
-- Музыка
---------------------------------------------------------------------

local FADE = 1.5
local currentMusic

-- Какая музыка должна играть там, где сейчас игрок
local function musicForZone()
	local zone = player:GetAttribute("Zone") or ""
	if zone ~= "" and zone ~= "Safe" then
		local name = "Music" .. zone
		if Sounds.List[name] and Sounds.List[name].Id ~= 0 then
			return name
		end
	end
	return "MusicLobby"
end

local function updateMusic()
	local chased = player:GetAttribute("ChasedBy") ~= nil
	local wanted = chased and "ChaseMusic" or musicForZone()
	if wanted == currentMusic then
		return
	end
	if currentMusic then
		Sfx.Fade(currentMusic, 0, FADE)
	end
	currentMusic = wanted
	Sfx.Fade(wanted, Sfx.Volume(wanted), chased and 0.3 or FADE)
end

player:GetAttributeChangedSignal("Zone"):Connect(updateMusic)
player:GetAttributeChangedSignal("ChasedBy"):Connect(updateMusic)
updateMusic()

---------------------------------------------------------------------
-- Беговая дорожка
---------------------------------------------------------------------

local function updateTreadmill()
	Sfx.SetLoop("TreadmillRun", player:GetAttribute("OnTreadmill") == true)
end
player:GetAttributeChangedSignal("OnTreadmill"):Connect(updateTreadmill)
updateTreadmill()
