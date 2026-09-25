-- Treadmill: что видит и делает игрок на беговой дорожке.
--
--  * прыжок (пробел или кнопка прыжка на телефоне) — сойти с дорожки;
--  * над головой всплывает прибавка скорости и падает вниз.
--
-- Сама скорость начисляется на сервере, клиент её только показывает.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Format = require(ReplicatedStorage.Shared.Format)

local player = Players.LocalPlayer
local leaveEvent = Remotes.Event("LeaveTreadmill")
local popupEvent = Remotes.Event("SpeedPopup")

local POPUP_TIME = 0.8
local POPUP_FALL = 2 -- на сколько студов цифра опускается, пока исчезает

---------------------------------------------------------------------
-- Прыжок = сойти с дорожки
---------------------------------------------------------------------

-- JumpRequest срабатывает и на пробел, и на кнопку прыжка на телефоне
UserInputService.JumpRequest:Connect(function()
	if player:GetAttribute("OnTreadmill") then
		leaveEvent:FireServer()
	end
end)

---------------------------------------------------------------------
-- Всплывающая цифра
---------------------------------------------------------------------

local function showPopup(amount)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeedPopup"
	gui.Size = UDim2.fromScale(4, 1.2)
	gui.StudsOffset = Vector3.new(math.random(-8, 8) / 10, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "+" .. Format.Number(amount)
	label.TextColor3 = Color3.fromRGB(250, 9, 9)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui

	gui.Parent = character

	-- Цифра съезжает вниз и растворяется
	local info = TweenInfo.new(POPUP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, {
		StudsOffset = gui.StudsOffset - Vector3.new(0, POPUP_FALL, 0),
	}):Play()
	TweenService:Create(label, info, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	task.delay(POPUP_TIME, function()
		gui:Destroy()
	end)
end

popupEvent.OnClientEvent:Connect(showPopup)
