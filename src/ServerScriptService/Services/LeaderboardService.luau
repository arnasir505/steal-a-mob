-- LeaderboardService: общая таблица лидеров по доходу в секунду (все серверы).
--
--  * таблица Roblox справа сверху (leaderstats, её делает EconomyService)
--    показывает игроков только ЭТОГО сервера;
--  * здесь — лучшие игроки ВСЕХ серверов. Раз в UpdateInterval секунд доход
--    игроков записывается в OrderedDataStore, а топ читается оттуда же;
--  * табло: деталь или модель с именем IncomeLeaderboard где угодно в Workspace.
--    Таблица появится на её лицевой стороне (Front — куда смотрит деталь).
--    Можно поставить несколько табло.
--
-- Работает только с доступом к DataStore: в опубликованной игре — всегда,
-- в Studio — если включено Game Settings → Security → Enable Studio Access to API Services.
--
-- Для интерфейса (этап 11): Remotes.Function("GetLeaderboard") вернёт последний топ:
--   { { Rank = 1, UserId = 123, Name = "...", Income = 5000 }, ... }

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local PlotBuilder = require(script.Parent.PlotBuilder)

local L = GameConfig.Leaderboard

local LeaderboardService = {}

local store = DataStoreService:GetOrderedDataStore(L.StoreName)
local lastSaved = {} -- [player] = доход, который уже записан (не пишем одно и то же)
local names = {}     -- [userId] = имя (запрос имени — это запрос в интернет)
local boards = {}    -- { List = Frame } — табло в мире
local top = {}       -- последний прочитанный топ
local warned = false

-- DataStore недоступен (например, в Studio без API Services) — говорим один раз
local function warnOnce(err)
	if not warned then
		warned = true
		warn("[LeaderboardService] Нет доступа к DataStore, общая таблица не обновляется: "
			.. tostring(err) .. ". В Studio включи Game Settings → Security → Enable Studio Access to API Services.")
	end
end

---------------------------------------------------------------------
-- Запись и чтение
---------------------------------------------------------------------

local function saveIncome(player)
	-- Берём из атрибута: когда игрок выходит, EconomyService уже успевает забыть
	-- его доход, а атрибут живёт до конца. OrderedDataStore хранит только целые числа.
	local income = math.min(math.floor(player:GetAttribute("IncomePerSecond") or 0), 2 ^ 53)
	if income <= 0 or lastSaved[player] == income then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(tostring(player.UserId), income)
	end)
	if ok then
		if player.Parent then
			lastSaved[player] = income
		end
	else
		warnOnce(err)
	end
end

local function nameOf(userId)
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = player and player.Name
	if not name then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = ok and result or ("Player " .. userId)
	end
	names[userId] = name
	return name
end

local function loadTop()
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, L.TopCount)
	end)
	if not ok then
		warnOnce(pages)
		return nil
	end
	local list = {}
	for rank, entry in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(entry.key) or 0
		table.insert(list, {
			Rank = rank,
			UserId = userId,
			Name = nameOf(userId),
			Income = entry.value,
		})
	end
	return list
end

---------------------------------------------------------------------
-- Табло в мире
---------------------------------------------------------------------

local function makeBoard(part)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "IncomeLeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	background.BackgroundTransparency = 0.15
	background.Active = false
	background.Parent = gui

	-- local title = Instance.new("TextLabel")
	-- title.Size = UDim2.fromScale(1, 0.14)
	-- title.BackgroundTransparency = 1
	-- title.Font = Enum.Font.GothamBlack
	-- title.TextScaled = true
	-- title.TextColor3 = Color3.fromRGB(255, 215, 80)
	-- title.Text = "Top Income / s"
	-- title.Parent = background

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Position = UDim2.fromScale(0.04, 0.04)
	list.Size = UDim2.fromScale(0.92, 0.92)
	list.BackgroundTransparency = 1
	list.Active = false
	list.Parent = background

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	gui.Parent = part
	table.insert(boards, { List = list })
end

local RANK_COLORS = {
	Color3.fromRGB(255, 215, 80),  -- золото
	Color3.fromRGB(210, 215, 225), -- серебро
	Color3.fromRGB(215, 140, 80),  -- бронза
}

local function render(board)
	for _, child in ipairs(board.List:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local function row(order, text, color)
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.fromScale(1, 1 / L.TopCount)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = color
		label.Text = text
		label.Parent = board.List
	end
	if #top == 0 then
		row(1, "No data yet", Color3.fromRGB(200, 200, 200))
		return
	end
	for _, entry in ipairs(top) do
		row(entry.Rank, string.format("#%d  %s  —  $%s/s", entry.Rank, entry.Name, Format.Number(entry.Income)),
			RANK_COLORS[entry.Rank] or Color3.fromRGB(235, 235, 235))
	end
end

-- Записать доходы всех, прочитать топ и обновить табло
function LeaderboardService.Update()
	for _, player in ipairs(Players:GetPlayers()) do
		saveIncome(player)
	end
	local list = loadTop()
	if list then
		top = list
	end
	for _, board in ipairs(boards) do
		render(board)
	end
	return top
end

function LeaderboardService.GetTop()
	return top
end

function LeaderboardService.Init()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant.Name == "IncomeLeaderboard" and (descendant:IsA("Model") or descendant:IsA("BasePart")) then
			local part = PlotBuilder.ResolvePart(descendant)
			if part then
				makeBoard(part)
			end
		end
	end
	if #boards == 0 then
		warn("[LeaderboardService] В Workspace нет табло IncomeLeaderboard — общий топ"
			.. " пока виден только командой !top. Поставь деталь с именем IncomeLeaderboard.")
	end

	Remotes.Function("GetLeaderboard").OnServerInvoke = function()
		return top
	end

	-- Уходящего игрока записываем сразу, чтобы его доход не потерялся
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(saveIncome, player)
		lastSaved[player] = nil
	end)

	task.spawn(function()
		task.wait(10) -- дать игрокам загрузиться
		while true do
			local ok, err = pcall(LeaderboardService.Update)
			if not ok then
				warn("[LeaderboardService] Ошибка обновления: " .. tostring(err))
			end
			task.wait(L.UpdateInterval)
		end
	end)
end

return LeaderboardService
