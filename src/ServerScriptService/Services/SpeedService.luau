-- SpeedService: скорость игрока.
--
-- Три вещи:
--  1. Считает настоящую скорость персонажа (Humanoid.WalkSpeed) из статы "Скорость".
--     Стата растёт бесконечно, а WalkSpeed растёт логарифмически и упирается в предел —
--     иначе персонаж начнёт пролетать сквозь стены.
--  2. Беговая дорожка: пока игрок стоит на ней, стата растёт.
--  3. Проверяет, не двигается ли игрок быстрее разрешённого, и возвращает назад.
--
-- Скорость меняется ТОЛЬКО через EconomyService.AddSpeed — этот сервис
-- сам замечает изменение через атрибут игрока и обновляет WalkSpeed.
--
-- Другим сервисам:
--   SpeedService.MarkTeleport(player)     -- честный телепорт, не считать нарушением
--   SpeedService.AllowBurst(player, 1.5)  -- отталкивание боссом или мечом (этапы 5-6)
--   SpeedService.SetTreadmill(player, part)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PassService = require(script.Parent.PassService)
local TrailService = require(script.Parent.TrailService)

local S = GameConfig.Speed
local T = GameConfig.Treadmill

local SpeedService = {}

local treadmills = {}   -- [player] = деталь дорожки его участка
local tracking = {}     -- [player] = { Position, Strikes, BurstUntil }
local walkSpeeds = {}   -- [player] = посчитанный сервером WalkSpeed

---------------------------------------------------------------------
-- Расчёт скорости
---------------------------------------------------------------------

-- Геймпасс x2 скорость. Множитель применяется при расчёте, а не к сохранённому
-- числу: иначе при каждом заходе в игру скорость удваивалась бы заново.
local function passMultiplier(player)
	return player:GetAttribute("Pass_X2Speed") and 2 or 1
end

-- Скорость, которая сравнивается со скоростью босса (этап 5).
-- Учитывает вес яйца в руках: тяжёлое яйцо замедляет.
function SpeedService.GetEffectiveSpeed(player)
	local stat = EconomyService.GetSpeed(player) * passMultiplier(player)
	local carried = player:GetAttribute("CarryWeight")
	if carried and carried > 0 then
		return Formulas.EffectiveSpeed(stat, carried)
	end
	return stat
end

function SpeedService.GetWalkSpeed(player)
	return Formulas.WalkSpeed(SpeedService.GetEffectiveSpeed(player))
end

-- Ставит персонажу настоящую скорость
function SpeedService.Apply(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local walkSpeed = SpeedService.GetWalkSpeed(player)
	walkSpeeds[player] = walkSpeed
	player:SetAttribute("WalkSpeed", walkSpeed)
	if humanoid then
		humanoid.WalkSpeed = walkSpeed
	end
end

---------------------------------------------------------------------
-- Беговая дорожка
---------------------------------------------------------------------

-- Множитель тренировки: трейл x геймпасс. Бонус друзей добавится на этапе 9.
function SpeedService.TrainingMultiplier(player)
	return TrailService.GetMultiplier(player) * passMultiplier(player)
end

function SpeedService.GetTreadmillGain(player)
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	return Formulas.TreadmillGain(data.TreadmillLevel, SpeedService.TrainingMultiplier(player))
end

function SpeedService.SetTreadmill(player, part)
	treadmills[player] = part
end

-- Стоит ли игрок на своей дорожке
local function isOnTreadmill(player)
	local part = treadmills[player]
	if not part or not part.Parent then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local offset = part.CFrame:PointToObjectSpace(root.Position)
	return math.abs(offset.X) <= part.Size.X / 2 + 1
		and math.abs(offset.Z) <= part.Size.Z / 2 + 1
		and offset.Y > 0
		and offset.Y <= T.StandHeight
end

function SpeedService.UpgradeTreadmill(player)
	local data = DataService.Get(player)
	if not data then
		return false
	end
	if data.TreadmillLevel >= T.MaxLevel then
		Remotes.Notify(player, "Max treadmill", "Your treadmill is fully upgraded.")
		return false
	end
	local cost = Formulas.TreadmillUpgradeCost(data.TreadmillLevel)
	if not EconomyService.TrySpend(player, cost) then
		Remotes.Notify(player, "Not enough money", "You need $" .. Format.Number(cost))
		return false
	end
	data.TreadmillLevel = data.TreadmillLevel + 1
	player:SetAttribute("TreadmillLevel", data.TreadmillLevel)
	Remotes.Notify(player, "Treadmill upgraded", "Level " .. data.TreadmillLevel
		.. " — +" .. Format.Number(SpeedService.GetTreadmillGain(player)) .. " speed/s")
	return true
end

-- Текст на табличке дорожки
function SpeedService.GetTreadmillText(player)
	local data = DataService.Get(player)
	if not data then
		return ""
	end
	local gain = SpeedService.GetTreadmillGain(player)
	if data.TreadmillLevel >= T.MaxLevel then
		return "Treadmill Lv." .. data.TreadmillLevel .. "\n+" .. Format.Number(gain) .. " speed/s"
	end
	return "Treadmill Lv." .. data.TreadmillLevel
		.. "\n+" .. Format.Number(gain) .. " speed/s"
		.. "\nUpgrade: $" .. Format.Number(Formulas.TreadmillUpgradeCost(data.TreadmillLevel))
end

---------------------------------------------------------------------
-- Проверка скорости
---------------------------------------------------------------------

-- Честный телепорт (появление на участке, сброс раунда): забываем прошлую точку
function SpeedService.MarkTeleport(player)
	local state = tracking[player]
	if state then
		state.Position = nil
		state.Strikes = 0
	end
end

-- Разрешить короткий рывок (отталкивание боссом или мечом)
function SpeedService.AllowBurst(player, seconds)
	local state = tracking[player]
	if state then
		state.BurstUntil = os.clock() + (seconds or 1)
	end
end

local function checkMovement(player, deltaTime)
	local state = tracking[player]
	if not state then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		state.Position = nil
		return
	end
	-- Пока игрока отталкивают, проверять нельзя
	if state.BurstUntil and os.clock() < state.BurstUntil then
		state.Position = root.Position
		return
	end

	local last = state.Position
	state.Position = root.Position
	if not last then
		return
	end

	-- Считаем только движение по земле: падение и прыжки не в счёт
	local moved = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(last.X, 0, last.Z)).Magnitude
	local allowed = (walkSpeeds[player] or S.BaseWalkSpeed) * deltaTime * S.CheckTolerance + S.CheckSlack
	if moved <= allowed then
		state.Strikes = 0
		return
	end

	state.Strikes = (state.Strikes or 0) + 1
	if state.Strikes < S.CheckStrikes then
		return
	end
	state.Strikes = 0
	state.Position = last
	root.CFrame = CFrame.new(last)
	warn("[SpeedService] " .. player.Name .. " двигался слишком быстро: "
		.. string.format("%.0f", moved) .. " > " .. string.format("%.0f", allowed))
end

---------------------------------------------------------------------
-- Запуск
---------------------------------------------------------------------

local function onCharacterAdded(player)
	SpeedService.MarkTeleport(player)
	task.defer(SpeedService.Apply, player)
end

local function onProfileLoaded(player, data)
	tracking[player] = { Strikes = 0 }
	player:SetAttribute("TreadmillLevel", data.TreadmillLevel)
	SpeedService.Apply(player)

	player.CharacterAdded:Connect(function()
		onCharacterAdded(player)
	end)

	-- Проверка геймпасса ходит в интернет; как узнаем ответ, пересчитаем скорость
	task.spawn(function()
		PassService.Has(player, "X2Speed")
		if player.Parent then
			SpeedService.Apply(player)
		end
	end)

	-- Стата скорости меняется только через EconomyService — ловим её через атрибут
	player:GetAttributeChangedSignal("Speed"):Connect(function()
		SpeedService.Apply(player)
	end)
	-- Вес яйца в руках (этап 6) тоже меняет скорость
	player:GetAttributeChangedSignal("CarryWeight"):Connect(function()
		SpeedService.Apply(player)
	end)
end

local function tick(deltaTime)
	for _, player in ipairs(Players:GetPlayers()) do
		if DataService.Get(player) then
			if isOnTreadmill(player) then
				local gain = SpeedService.GetTreadmillGain(player) * deltaTime
				if gain > 0 then
					EconomyService.AddSpeed(player, gain)
				end
			end
			checkMovement(player, deltaTime)
		end
	end
end

function SpeedService.Init()
	DataService.ProfileLoaded:Connect(onProfileLoaded)

	Players.PlayerRemoving:Connect(function(player)
		treadmills[player] = nil
		tracking[player] = nil
		walkSpeeds[player] = nil
	end)

	PassService.PassGranted:Connect(function(player, passName)
		if passName == "X2Speed" then
			SpeedService.Apply(player)
		end
	end)

	task.spawn(function()
		while true do
			local deltaTime = task.wait(S.CheckInterval)
			local ok, err = pcall(tick, deltaTime)
			if not ok then
				warn("[SpeedService] Ошибка в цикле скорости: " .. tostring(err))
			end
		end
	end)
end

return SpeedService
