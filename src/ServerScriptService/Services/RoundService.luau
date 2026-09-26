-- RoundService: раунды по 5 минут.
--
-- Порядок сброса:
--   1. за 10 секунд — предупреждение всем игрокам;
--   2. все яйца вне рюкзаков удаляются (и на земле, и в руках);
--   3. всех игроков телепортирует на свой участок в safe zone;
--   4. ворота биомов закрываются на пару секунд;
--   5. спавнятся новые яйца;
--   6. ворота открываются, раунд пошёл.
--
-- Почему яйца удаляются ДО телепорта: иначе телепорт сам заносил бы игрока
-- с яйцом в safe zone, и кража засчитывалась бы бесплатно. Донести надо успеть.
--
-- Время конца раунда лежит в атрибуте ReplicatedStorage.RoundEndsAt (os.time),
-- чтобы интерфейс на этапе 11 мог показать таймер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local EggService = require(script.Parent.EggService)
local PlotService = require(script.Parent.PlotService)
local WorldService = require(script.Parent.WorldService)

local R = GameConfig.Round

local RoundService = {}

local roundEndsAt = 0
local resetting = false

local startedEvent = Instance.new("BindableEvent")
RoundService.RoundStarted = startedEvent.Event -- для боссов (этап 5)

function RoundService.GetSecondsLeft()
	return math.max(0, roundEndsAt - os.time())
end

function RoundService.IsResetting()
	return resetting
end

local function setRoundEnd(seconds)
	roundEndsAt = os.time() + seconds
	ReplicatedStorage:SetAttribute("RoundEndsAt", roundEndsAt)
end

-- Всех в safe zone, на свои участки
local function sendEveryoneHome()
	for _, player in ipairs(Players:GetPlayers()) do
		PlotService.SendHome(player)
	end
end

local function resetRound()
	resetting = true
	ReplicatedStorage:SetAttribute("RoundResetting", true)

	-- 1. Яйца вне рюкзаков пропадают — сначала, чтобы телепорт не засчитал кражу
	EggService.ClearAll()

	-- 2. Всех домой и закрываем проходы
	sendEveryoneHome()
	WorldService.SetGatesClosed(true)
	Remotes.NotifyAll("New round", "Eggs are respawning...")

	task.wait(R.CloseDuration)

	-- 3. Новые яйца и открываем биомы
	EggService.SpawnRound()
	WorldService.SetGatesClosed(false)

	resetting = false
	ReplicatedStorage:SetAttribute("RoundResetting", false)
	setRoundEnd(R.Duration)
	startedEvent:Fire()
end

function RoundService.ForceReset()
	if not resetting then
		task.spawn(resetRound)
	end
end

function RoundService.Init()
	ReplicatedStorage:SetAttribute("RoundResetting", false)
	setRoundEnd(R.Duration)

	task.spawn(function()
		-- Первый спавн яиц при старте сервера
		EggService.SpawnRound()
		startedEvent:Fire()

		local warned = false
		while true do
			task.wait(1)
			local left = RoundService.GetSecondsLeft()

			if not warned and left <= R.WarningBefore and left > 0 then
				warned = true
				Remotes.NotifyAll("Round ending", "Get to the safe zone! " .. Format.Time(left))
			end

			if left <= 0 then
				warned = false
				local ok, err = pcall(resetRound)
				if not ok then
					warn("[RoundService] Ошибка при сбросе раунда: " .. tostring(err))
					resetting = false
					setRoundEnd(R.Duration)
				end
			end
		end
	end)

	print("[RoundService] Раунд " .. Format.Time(R.Duration) .. ", предупреждение за "
		.. R.WarningBefore .. " сек")
end

return RoundService
