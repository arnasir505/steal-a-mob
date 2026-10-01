-- EggDrop: кнопка "бросить яйцо".
--
-- G на клавиатуре, Y на геймпаде. Кнопку Drop на экране (для всех, и для телефона)
-- рисует интерфейс — UI/ChaseOverlay.
-- Кнопка есть, только пока игрок несёт яйцо. Клиент лишь просит —
-- сервер сам проверит, что яйцо в руках и что игрок не в safe zone.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local dropEvent = Remotes.Event("DropEgg")
local ACTION = "DropEgg"

local bound = false

local function onAction(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	dropEvent:FireServer()
	return Enum.ContextActionResult.Sink
end

-- Несёт ли игрок яйцо: сервер пишет его редкость в атрибут CarryRarity
local function refresh()
	local carrying = (player:GetAttribute("CarryRarity") or "") ~= ""
	if carrying and not bound then
		bound = true
		-- false: свою кнопку на экране рисует интерфейс
		ContextActionService:BindAction(ACTION, onAction, false, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
	elseif not carrying and bound then
		bound = false
		ContextActionService:UnbindAction(ACTION)
	end
end

player:GetAttributeChangedSignal("CarryRarity"):Connect(refresh)
refresh()
