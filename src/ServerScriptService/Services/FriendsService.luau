-- FriendsService: бонус за друзей на сервере.
--
-- +10% за каждого друга, который сейчас на этом же сервере, максимум +40%
-- (GameConfig.FriendsBonus, формула — Formulas.FriendsBonus).
-- Бонус действует на доход в секунду и на тренировку скорости (беговую дорожку).
-- На офлайн-доход не действует.
--
-- Бонус лежит в атрибуте игрока FriendsBonus (0.1 = +10%). Его читают
-- EconomyService (доход) и SpeedService (дорожка), его же покажет интерфейс.
-- Число друзей на сервере — атрибут FriendsOnline.
--
-- Дружбу проверяет Roblox (player:IsFriendsWith) — это запрос в интернет,
-- поэтому каждую пару проверяем один раз, когда кто-то из них заходит.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlotService = require(script.Parent.PlotService)

local FriendsService = {}

local friends = {}    -- [player] = { [другой игрок] = true } — друзья на этом сервере
local testCounts = {} -- [player] = число: подменить число друзей (тестовая команда !friends)

local function countFriends(player)
	if testCounts[player] then
		return testCounts[player]
	end
	local n = 0
	for other in pairs(friends[player] or {}) do
		if other.Parent then
			n = n + 1
		end
	end
	return n
end

-- Пересчитывает бонус. announce = true — сообщить игроку, если бонус изменился.
local function refresh(player, announce)
	if not player.Parent then
		return
	end
	local count = countFriends(player)
	local bonus = Formulas.FriendsBonus(count)
	local old = player:GetAttribute("FriendsBonus") or 0
	player:SetAttribute("FriendsBonus", bonus)
	player:SetAttribute("FriendsOnline", count)
	if bonus == old then
		return
	end
	PlotService.RecalcIncome(player)
	if announce then
		if bonus > 0 then
			Remotes.Notify(player, "Friend bonus",
				"+" .. math.floor(bonus * 100 + 0.5) .. "% income and training (" .. count .. " friends here)")
		else
			Remotes.Notify(player, "Friend bonus", "No friends on this server anymore.")
		end
	end
end

function FriendsService.GetBonus(player)
	return player:GetAttribute("FriendsBonus") or 0
end

function FriendsService.GetCount(player)
	return countFriends(player)
end

-- Только для тестов: притвориться, что на сервере n друзей (nil — по-настоящему)
function FriendsService.SetTestCount(player, n)
	testCounts[player] = n
	refresh(player, true)
end

local function onPlayerAdded(player)
	friends[player] = friends[player] or {}
	player:SetAttribute("FriendsBonus", 0)
	player:SetAttribute("FriendsOnline", 0)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			task.spawn(function()
				local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
				if ok and isFriend and player.Parent and other.Parent then
					friends[player] = friends[player] or {}
					friends[other] = friends[other] or {}
					friends[player][other] = true
					friends[other][player] = true
					refresh(player, true)
					refresh(other, true)
				end
			end)
		end
	end
end

local function onPlayerRemoving(player)
	local list = friends[player]
	friends[player] = nil
	testCounts[player] = nil
	for other in pairs(list or {}) do
		if friends[other] then
			friends[other][player] = nil
		end
		refresh(other, true)
	end
end

function FriendsService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return FriendsService
