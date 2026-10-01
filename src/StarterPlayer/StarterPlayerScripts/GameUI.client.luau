-- GameUI: интерфейс игры. Собирает экран, магазин, индекс и экран погони
-- из модулей в папке UI. Картинки — Config/UIAssets.
--
-- Клиент только показывает и просит: деньги, покупки и всё остальное
-- проверяет сервер.

local Players = game:GetService("Players")

local Kit = require(script.Parent:WaitForChild("UI"):WaitForChild("Kit"))
local Hud = require(script.Parent.UI.Hud)
local ShopWindow = require(script.Parent.UI.ShopWindow)
local IndexWindow = require(script.Parent.UI.IndexWindow)
local ChaseOverlay = require(script.Parent.UI.ChaseOverlay)

local player = Players.LocalPlayer

-- Ждём данные игрока: без них нечего показывать
if not player:GetAttribute("DataLoaded") then
	player:GetAttributeChangedSignal("DataLoaded"):Wait()
end

local screen = Kit.new("ScreenGui", {
	Name = "GameUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = false,
	DisplayOrder = 1, -- выше красной рамки погони (ChaseOverlay)
	Parent = player:WaitForChild("PlayerGui"),
})

local shop = ShopWindow.Build(screen, player)
local index = IndexWindow.Build(screen)

Hud.Build(screen, player, {
	-- toggle = true (кнопка Shop): открыт — закрыть. Иначе открыть на нужной вкладке.
	OpenShop = function(pageName, toggle)
		if toggle and shop.Window.IsOpen() then
			shop.Window.Close()
		else
			shop.Open(pageName)
		end
	end,
	ToggleIndex = index.Window.Toggle,
})

ChaseOverlay.Build(screen, player)
