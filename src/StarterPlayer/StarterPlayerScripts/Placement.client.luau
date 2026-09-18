-- Placement: кнопка "поставить яйцо на участок".
--
-- Клиент только сообщает серверу "хочу поставить". Где именно встанет предмет,
-- решает сервер по настоящему положению персонажа — так игрок не сможет
-- поставить яйцо через стену или на чужой участок.
--
-- Кнопка E совпадает с подсказками (ProximityPrompt). Чтобы они не спорили,
-- пока рядом видна любая подсказка, запрос на постановку не отправляется:
-- в этот момент E значит "убрать предмет", а не "поставить".

local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local placeEvent = Remotes.Event("PlaceItem")
local ACTION = "PlaceItem"

local visiblePrompts = 0

ProximityPromptService.PromptShown:Connect(function()
	visiblePrompts = visiblePrompts + 1
end)

ProximityPromptService.PromptHidden:Connect(function()
	visiblePrompts = math.max(0, visiblePrompts - 1)
end)

local function onAction(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if visiblePrompts > 0 then
		return Enum.ContextActionResult.Pass -- рядом подсказка, пусть работает она
	end
	placeEvent:FireServer()
	return Enum.ContextActionResult.Sink
end

-- true = на телефоне появится кнопка на экране
ContextActionService:BindAction(ACTION, onAction, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
ContextActionService:SetTitle(ACTION, "Place")
