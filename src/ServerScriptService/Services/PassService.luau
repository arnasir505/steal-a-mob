-- PassService: проверяет, куплен ли у игрока геймпасс.
--   PassService.Has(player, "X2Money") -> true / false
-- Геймпассы с Id = 0 (ещё не созданные) считаются не купленными
-- (кроме тестовой команды !pass в Studio).
-- Окно покупки открывает ProductService.PromptPass.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Products = require(ReplicatedStorage.Shared.Config.Products)

local PassService = {}

local cache = {} -- [player] = { [passName] = true/false }

local grantedEvent = Instance.new("BindableEvent")
PassService.PassGranted = grantedEvent.Event -- (player, passName) — куплен прямо в игре

local function remember(player, passName, owns)
	if not cache[player] then
		cache[player] = {}
	end
	cache[player][passName] = owns
	player:SetAttribute("Pass_" .. passName, owns) -- клиент видит это для интерфейса
end

function PassService.Has(player, passName)
	local pass = Products.GamePasses[passName]
	if not pass then
		return false
	end
	local playerCache = cache[player]
	if playerCache and playerCache[passName] ~= nil then
		return playerCache[passName]
	end
	if pass.Id == 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
	end)
	if ok and player.Parent then
		remember(player, passName, owns)
		return owns
	end
	return false -- при ошибке не запоминаем, проверим в следующий раз
end

-- Только для тестов в Studio: притвориться, что геймпасс куплен (команда !pass)
function PassService.GrantForTesting(player, passName)
	if not Products.GamePasses[passName] then
		return false
	end
	remember(player, passName, true)
	grantedEvent:Fire(player, passName)
	return true
end

function PassService.Init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for passName, pass in pairs(Products.GamePasses) do
			if pass.Id == passId then
				remember(player, passName, true)
				grantedEvent:Fire(player, passName)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

return PassService
