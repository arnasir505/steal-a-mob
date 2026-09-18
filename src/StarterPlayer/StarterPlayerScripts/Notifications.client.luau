-- Notifications: показывает сообщения сервера стандартной всплывашкой Roblox.
-- Это временно: на этапе 11 сделаем свой интерфейс.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

Remotes.Event("Notify").OnClientEvent:Connect(function(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = tostring(title),
			Text = tostring(text),
			Duration = 4,
		})
	end)
end)
