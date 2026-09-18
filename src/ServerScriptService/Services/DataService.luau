-- DataService: загрузка и сохранение данных игроков.
--
-- Что умеет:
--  * загружает данные при входе и дополняет их новыми полями из DataTemplate;
--  * "замок сессии": данные игрока одновременно открыты только на одном сервере,
--    поэтому при быстром переходе между серверами прогресс не теряется и не дублируется;
--  * автосохранение, сохранение при выходе и при выключении сервера;
--  * если данные не загрузились, игрока кикает, и мы НИКОГДА не перезаписываем
--    его прогресс пустыми данными.
--
-- Как использовать из других сервисов:
--   local data = DataService.Get(player)       -- таблица данных или nil
--   DataService.ProfileLoaded:Connect(function(player, data) ... end)
--   Данные можно менять прямо в таблице — они сохранятся сами.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local DataTemplate = require(script.Parent.DataTemplate)

local DataService = {}

local store = DataStoreService:GetDataStore(GameConfig.DataStoreName)

local profiles = {}  -- [player] = data
local sessions = {}  -- [player] = { OfflineSeconds = number }

local loadedEvent = Instance.new("BindableEvent")
DataService.ProfileLoaded = loadedEvent.Event       -- (player, data)

local releasingEvent = Instance.new("BindableEvent")
DataService.ProfileReleasing = releasingEvent.Event -- (player, data) перед последним сохранением

-- Если сервер не обновлял замок так долго, считаем, что он упал, и забираем данные
local LOCK_EXPIRE_SECONDS = GameConfig.AutosaveInterval * 3
local LOAD_ATTEMPTS = 6
local LOCKED_RETRY_DELAY = 5

---------------------------------------------------------------------
-- Вспомогательное
---------------------------------------------------------------------

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Добавляет в data поля, которых нет, но которые есть в шаблоне
local function reconcile(data, template)
	for key, value in pairs(template) do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
end

local function keyFor(userId)
	return "Player_" .. userId
end

-- Повторяет запрос к DataStore при ошибке (2, 4, 8 секунд ожидания)
local function withRetries(fn, attempts)
	local lastError
	for attempt = 1, attempts do
		local ok, err = pcall(fn)
		if ok then
			return true
		end
		lastError = err
		warn("[DataService] Ошибка DataStore (попытка " .. attempt .. "): " .. tostring(err))
		if attempt < attempts then
			task.wait(2 ^ attempt)
		end
	end
	return false, lastError
end

---------------------------------------------------------------------
-- Загрузка
---------------------------------------------------------------------

-- Пытается забрать данные и поставить замок.
-- Возвращает: успех запроса, "ok" или "locked", данные
local function tryLoadAndLock(userId)
	local status, loaded
	local ok = withRetries(function()
		store:UpdateAsync(keyFor(userId), function(old)
			local now = os.time()
			local lock = old and old.SessionLock
			if lock and lock.JobId ~= game.JobId and now - lock.Time < LOCK_EXPIRE_SECONDS then
				status = "locked"
				return nil -- ничего не записываем
			end
			local data = old or deepCopy(DataTemplate)
			data.SessionLock = { JobId = game.JobId, Time = now }
			status = "ok"
			loaded = data
			return data
		end)
	end, 3)
	return ok, status, loaded
end

local function save(player, data, releaseLock)
	local userId = player.UserId
	data.LastOnline = os.time()
	local ok, err = withRetries(function()
		store:UpdateAsync(keyFor(userId), function(old)
			if not releaseLock and profiles[player] ~= data then
				return nil -- игрок уже вышел и замок отпущен — автосохранение не нужно
			end
			local lock = old and old.SessionLock
			if lock and lock.JobId ~= game.JobId then
				-- Данные уже забрал другой сервер — не затираем их
				warn("[DataService] Замок у другого сервера, сохранение отменено: " .. userId)
				return nil
			end
			if releaseLock then
				data.SessionLock = nil
			else
				data.SessionLock = { JobId = game.JobId, Time = os.time() }
			end
			return data
		end)
	end, 3)
	if not ok then
		warn("[DataService] Не удалось сохранить " .. userId .. ": " .. tostring(err))
	end
	return ok
end

local function loadPlayer(player)
	local data
	for _ = 1, LOAD_ATTEMPTS do
		local ok, status, loaded = tryLoadAndLock(player.UserId)
		if not ok then
			break -- DataStore недоступен
		end
		if status == "ok" then
			data = loaded
			break
		end
		-- Другой сервер ещё сохраняет данные этого игрока — подождём
		task.wait(LOCKED_RETRY_DELAY)
		if not player.Parent then
			return
		end
	end

	if not data then
		player:Kick("Could not load your data. Please rejoin in a minute.")
		return
	end

	-- Игрок вышел, пока мы грузили — сразу отпускаем замок
	if not player.Parent then
		save(player, data, true)
		return
	end

	reconcile(data, DataTemplate)

	local offlineSeconds = 0
	if data.LastOnline > 0 then
		offlineSeconds = math.max(0, os.time() - data.LastOnline)
	end
	data.Stats.JoinCount = data.Stats.JoinCount + 1

	profiles[player] = data
	sessions[player] = { OfflineSeconds = offlineSeconds }
	player:SetAttribute("DataLoaded", true)
	loadedEvent:Fire(player, data)
end

local function releasePlayer(player)
	local data = profiles[player]
	if not data then
		return
	end
	releasingEvent:Fire(player, data)
	profiles[player] = nil
	sessions[player] = nil
	save(player, data, true)
end

---------------------------------------------------------------------
-- Публичные функции
---------------------------------------------------------------------

function DataService.Get(player)
	return profiles[player]
end

-- Ждёт загрузки данных (для кода, который может запуститься раньше)
function DataService.WaitForData(player, timeout)
	local started = os.clock()
	while player.Parent and not profiles[player] do
		if timeout and os.clock() - started > timeout then
			return nil
		end
		task.wait(0.1)
	end
	return profiles[player]
end

-- Сколько секунд игрок был офлайн до этого входа
function DataService.GetOfflineSeconds(player)
	local session = sessions[player]
	return session and session.OfflineSeconds or 0
end

-- Только для тестов в Studio: сбросить прогресс игрока
function DataService.ResetForTesting(player)
	if not RunService:IsStudio() then
		return
	end
	local data = profiles[player]
	if not data then
		return
	end
	local lock = data.SessionLock
	for key in pairs(data) do
		data[key] = nil
	end
	for key, value in pairs(deepCopy(DataTemplate)) do
		data[key] = value
	end
	data.SessionLock = lock
end

function DataService.Start()
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(releasePlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, player)
	end

	-- Автосохранение
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			for player, data in pairs(profiles) do
				task.spawn(save, player, data, false)
			end
		end
	end)

	-- Сервер выключается: сохраняем всех
	game:BindToClose(function()
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			if profiles[player] then
				pending = pending + 1
				task.spawn(function()
					releasePlayer(player)
					pending = pending - 1
				end)
			end
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
