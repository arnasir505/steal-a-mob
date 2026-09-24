-- TimeChangeService: смена дня и ночи.
--
-- Крутит Lighting.ClockTime по кругу и плавно меняет общее освещение:
-- днём светло, ночью темно и синевато. Все числа — в GameConfig.DayNight.
--
-- Время считается только на сервере. Lighting реплицируется клиентам сам,
-- поэтому у всех игроков сервера одно и то же время суток — отдельный
-- клиентский скрипт не нужен.
--
--   TimeChangeService.GetClockTime()      -- текущий час (число, например 13.5)
--   TimeChangeService.SetClockTime(20)    -- поставить 20:00
--   TimeChangeService.SetEnabled(false)   -- остановить время (освещение замрёт)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local C = GameConfig.DayNight

local TimeChangeService = {}

local clockTime = C.StartClockTime -- своё время, чтобы не терять дробную часть
local running = false
local started = false
local sinceUpdate = 0

-- Сколько игровых часов проходит за одну реальную секунду
local hoursPerSecond = 24 / math.max(C.CycleMinutes, 0.01) / 60

---------------------------------------------------------------------
-- Расчёт освещения
---------------------------------------------------------------------

-- Плавная кривая вместо резкого перехода: 0 в начале, 1 в конце, без углов
local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 1 — полный день, 0 — полная ночь, между ними рассвет и закат
local function dayFactor(hour)
	local blend = math.max(C.BlendHours, 0.01)
	local sunrise = smoothstep((hour - (C.SunriseHour - blend / 2)) / blend)
	local sunset = 1 - smoothstep((hour - (C.SunsetHour - blend / 2)) / blend)
	return math.min(sunrise, sunset)
end

local function apply()
	Lighting.ClockTime = clockTime

	if not C.TintLighting then
		return
	end

	local t = dayFactor(clockTime)
	Lighting.Ambient = C.Night.Ambient:Lerp(C.Day.Ambient, t)
	Lighting.OutdoorAmbient = C.Night.OutdoorAmbient:Lerp(C.Day.OutdoorAmbient, t)
	Lighting.Brightness = C.Night.Brightness + (C.Day.Brightness - C.Night.Brightness) * t
end

---------------------------------------------------------------------
-- Внешние функции
---------------------------------------------------------------------

function TimeChangeService.GetClockTime()
	return clockTime
end

-- Поставить конкретный час. 0 — полночь, 12 — полдень, 20.5 — половина девятого вечера.
function TimeChangeService.SetClockTime(hour)
	clockTime = (tonumber(hour) or 0) % 24
	apply()
end

-- Включить или остановить ход времени. Освещение остаётся таким, каким было.
function TimeChangeService.SetEnabled(enabled)
	running = enabled and true or false
end

function TimeChangeService.IsEnabled()
	return running
end

---------------------------------------------------------------------
-- Запуск
---------------------------------------------------------------------

function TimeChangeService.Init()
	if started then
		return
	end
	started = true
	running = C.Enabled and true or false

	if running then
		apply()
	end
	-- Если время выключено, освещение не трогаем: остаётся то, что выставлено
	-- в Studio. Цикл всё равно подключаем, чтобы его можно было включить
	-- на ходу через TimeChangeService.SetEnabled(true) или команду !time go.

	-- Время идёт по реальному delta, поэтому просадки FPS его не замедляют.
	-- Освещение обновляем не каждый кадр, а раз в UpdateInterval секунд —
	-- этого хватает глазу и не грузит репликацию.
	RunService.Heartbeat:Connect(function(delta)
		if not running then
			return
		end

		clockTime = (clockTime + delta * hoursPerSecond) % 24

		sinceUpdate += delta
		if sinceUpdate < C.UpdateInterval then
			return
		end
		sinceUpdate = 0

		apply()
	end)
end

return TimeChangeService
