-- TrailService: трейлы (следы за игроком).
--
-- Трейл покупается за деньги, надет может быть только один.
-- Он даёт множитель к беговой дорожке (см. SpeedService) и виден за персонажем.
-- Сезонные трейлы (Seasonal = true) купить нельзя — их выдаёт календарь (этап 9).
--
--   TrailService.Buy(player, "BlueTrail")
--   TrailService.Equip(player, "BlueTrail")   -- "" снимает трейл
--   TrailService.GetMultiplier(player)        -- множитель к дорожке

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Items = require(ReplicatedStorage.Shared.Config.Items)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local TrailService = {}

---------------------------------------------------------------------
-- Внешний вид
---------------------------------------------------------------------

local function removeTrail(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local existing = root and root:FindFirstChild("PlayerTrail")
	if existing then
		existing:Destroy()
	end
	if root then
		for _, name in ipairs({ "TrailTop", "TrailBottom" }) do
			local attachment = root:FindFirstChild(name)
			if attachment then
				attachment:Destroy()
			end
		end
	end
end

local function applyTrail(player)
	local character = player.Character
	local data = DataService.Get(player)
	if not character or not data then
		return
	end
	removeTrail(character)

	local config = Items.Trails[data.EquippedTrail]
	if not config then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, 1.5, 0)
	top.Parent = root

	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -1.5, 0)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "PlayerTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(config.Color or Color3.fromRGB(255, 255, 255))
	trail.Lifetime = 0.6
	trail.LightEmission = 0.5
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = root
end

---------------------------------------------------------------------
-- Покупка и надевание
---------------------------------------------------------------------

function TrailService.Buy(player, trailId)
	local data = DataService.Get(player)
	local config = type(trailId) == "string" and Items.Trails[trailId]
	if not data or not config then
		return false
	end
	if data.Trails[trailId] then
		TrailService.Equip(player, trailId)
		return true
	end
	if config.Seasonal then
		Remotes.Notify(player, "Not for sale", "This trail comes from the daily calendar.")
		return false
	end
	if not EconomyService.TrySpend(player, config.Price) then
		Remotes.Notify(player, "Not enough money", "You need $" .. Format.Number(config.Price))
		return false
	end
	data.Trails[trailId] = true
	Remotes.Notify(player, "Trail bought", config.DisplayName)
	TrailService.Equip(player, trailId)
	return true
end

-- Выдать трейл бесплатно (календарь, награды)
function TrailService.Grant(player, trailId)
	local data = DataService.Get(player)
	if not data or not Items.Trails[trailId] then
		return false
	end
	data.Trails[trailId] = true
	return true
end

function TrailService.Equip(player, trailId)
	local data = DataService.Get(player)
	if not data then
		return false
	end
	if trailId == "" or trailId == nil then
		data.EquippedTrail = ""
		player:SetAttribute("EquippedTrail", "")
		applyTrail(player)
		return true
	end
	if type(trailId) ~= "string" or not Items.Trails[trailId] or not data.Trails[trailId] then
		return false
	end
	data.EquippedTrail = trailId
	player:SetAttribute("EquippedTrail", trailId)
	applyTrail(player)
	return true
end

-- Множитель к прибавке беговой дорожки от надетого трейла
function TrailService.GetMultiplier(player)
	local data = DataService.Get(player)
	local config = data and Items.Trails[data.EquippedTrail]
	return config and config.TreadmillMult or 1
end

function TrailService.Init()
	Remotes.Event("BuyTrail").OnServerEvent:Connect(function(player, trailId)
		TrailService.Buy(player, trailId)
	end)
	Remotes.Event("EquipTrail").OnServerEvent:Connect(function(player, trailId)
		TrailService.Equip(player, trailId)
	end)

	DataService.ProfileLoaded:Connect(function(player, data)
		player:SetAttribute("EquippedTrail", data.EquippedTrail)
		applyTrail(player)
		player.CharacterAdded:Connect(function()
			task.defer(applyTrail, player)
		end)
	end)
end

return TrailService
