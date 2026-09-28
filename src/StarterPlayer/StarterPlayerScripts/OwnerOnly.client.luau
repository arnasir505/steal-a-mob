-- OwnerOnly: кнопки и надписи, которые видит только хозяин участка.
--
-- Сервер помечает их тегом "OwnerOnly" и создаёт выключенными
-- (PlotBuilder.MakeOwnerOnly): Store/Sell у мобов и яиц, улучшение базы
-- и дорожки, цены улучшений. Здесь каждый игрок у себя включает только то,
-- что стоит на его участке. Хозяин — атрибут OwnerUserId у модели участка
-- (0 — участок свободен).
-- Атрибут Available = false значит "сейчас не нужно даже хозяину"
-- (например, база улучшена до конца).
--
-- Это только про то, что видно. Нажать чужую кнопку всё равно нельзя —
-- сервер сам проверяет, чей участок.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local TAG = "OwnerOnly"
local player = Players.LocalPlayer

local watchedPlots = {} -- [модель участка] = true: на смену хозяина уже подписались

-- Модель участка, в которой лежит объект
local function plotOf(instance)
	local node = instance.Parent
	while node and node ~= workspace do
		if node:GetAttribute("OwnerUserId") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function refresh(instance)
	local plot = plotOf(instance)
	local mine = plot ~= nil and plot:GetAttribute("OwnerUserId") == player.UserId
	instance.Enabled = mine and instance:GetAttribute("Available") ~= false
end

local function refreshPlot(plot)
	for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
		if instance:IsDescendantOf(plot) then
			refresh(instance)
		end
	end
end

local function watch(instance)
	refresh(instance)
	instance:GetAttributeChangedSignal("Available"):Connect(function()
		refresh(instance)
	end)

	-- Участок сменил хозяина (игрок зашёл или вышел) — пересчитываем всё на нём
	local plot = plotOf(instance)
	if plot and not watchedPlots[plot] then
		watchedPlots[plot] = true
		plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			refreshPlot(plot)
		end)
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
	watch(instance)
end
