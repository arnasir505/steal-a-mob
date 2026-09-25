-- SpeedService: скорость игрока.
--
-- Три вещи:
--  1. Считает настоящую скорость персонажа (Humanoid.WalkSpeed) из статы "Скорость".
--     Стата растёт бесконечно, а WalkSpeed растёт логарифмически и упирается в предел —
--     иначе персонаж начнёт пролетать сквозь стены.
--  2. Беговая дорожка: игрок встаёт на неё, прилипает к полотну, бежит на месте
--     и получает скорость короткими шагами. Спрыгивает прыжком (пробел или
--     кнопка прыжка на телефоне).
--  3. Проверяет, не двигается ли игрок быстрее разрешённого, и возвращает назад.
--
-- Скорость меняется ТОЛЬКО через EconomyService.AddSpeed — этот сервис
-- сам замечает изменение через атрибут игрока и обновляет WalkSpeed.
--
-- Другим сервисам:
--   SpeedService.MarkTeleport(player)     -- честный телепорт, не считать нарушением
--   SpeedService.AllowBurst(player, 1.5)  -- отталкивание боссом или мечом (этапы 5-6)
--   SpeedService.SetTreadmill(player, surface)

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

local popupEvent = Remotes.Event("SpeedPopup")

local SpeedService = {}

local treadmills = {}   -- [player] = поверхность дорожки его участка (PlotBuilder.GetTreadmillSurface)
local standing = {}     -- [player] = { Track, BlockedUntil, MustLeave }
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
		-- На дорожке игрок стоит на месте: скорость там всегда 0,
		-- иначе начисление скорости каждые 0.2 секунды сбрасывало бы это обратно
		humanoid.WalkSpeed = player:GetAttribute("OnTreadmill") and 0 or walkSpeed
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

function SpeedService.SetTreadmill(player, surface)
	if not surface then
		SpeedService.LeaveTreadmill(player)
	end
	treadmills[player] = surface
end

-- Стоит ли игрок на своей дорожке
local function isOnTreadmill(player)
	local surface = treadmills[player]
	if not surface then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local offset = surface.CFrame:PointToObjectSpace(root.Position)
	return math.abs(offset.X) <= surface.Size.X / 2 + 1
		and math.abs(offset.Z) <= surface.Size.Z / 2 + 1
		and offset.Y > 0
		and offset.Y <= T.StandHeight
end

---------------------------------------------------------------------
-- Прилипание к дорожке и бег на месте
---------------------------------------------------------------------

local function stopAnimation(player)
	local state = standing[player]
	if state and state.Track then
		state.Track:Stop(0.2)
		state.Track = nil
	end
end

local function playRunAnimation(player, humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = humanoid.RigType == Enum.HumanoidRigType.R6
		and T.RunAnimationR6
		or T.RunAnimationR15

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then
		warn("[SpeedService] Не удалось загрузить анимацию бега")
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.2)
	track:AdjustSpeed(T.RunAnimationSpeed)
	return track
end

-- Ставит игрока на полотно и включает бег на месте
local function enterTreadmill(player)
	local surface = treadmills[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not surface or not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	-- Куда лицом: вдоль полотна, в ту сторону, куда игрок уже смотрел
	local forward = surface.Forward
	if root.CFrame.LookVector:Dot(forward) < 0 then
		forward = -forward
	end

	-- Насколько поднять над полотном, чтобы ноги стояли ровно
	local lift = math.max(humanoid.HipHeight + root.Size.Y / 2, 3)
	local position = (surface.CFrame * CFrame.new(0, surface.Size.Y / 2 + lift, 0)).Position

	root.CFrame = CFrame.lookAt(position, position + forward)
	root.Anchored = true
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	SpeedService.MarkTeleport(player) -- это честный телепорт

	local state = standing[player] or {}
	state.Track = playRunAnimation(player, humanoid)
	standing[player] = state
	player:SetAttribute("OnTreadmill", true)
end

-- Снимает игрока с дорожки: спрыгнул, вышел, умер или потерял участок
function SpeedService.LeaveTreadmill(player, jump)
	local state = standing[player]
	if not player:GetAttribute("OnTreadmill") and not (state and state.Track) then
		return
	end
	stopAnimation(player)
	player:SetAttribute("OnTreadmill", false)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = false
	end
	if humanoid then
		humanoid.AutoRotate = true
		if jump and humanoid.Health > 0 then
			humanoid.Jump = true
		end
	end
	SpeedService.Apply(player) -- вернуть нормальный WalkSpeed
	SpeedService.MarkTeleport(player)

	state = standing[player] or {}
	-- Пока игрок не сойдёт с полотна, обратно не приклеиваем
	state.MustLeave = true
	state.BlockedUntil = os.clock() + T.ExitCooldown
	standing[player] = state
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
	-- Новый персонаж не приклеен: забываем всё, что было с дорожкой
	standing[player] = nil
	player:SetAttribute("OnTreadmill", false)
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
			checkMovement(player, deltaTime)
		end
	end
end

-- Отдельный цикл дорожки: он частый (раз в 0.2 секунды), а проверка скорости нет
local function treadmillTick()
	for _, player in ipairs(Players:GetPlayers()) do
		if DataService.Get(player) then
			local state = standing[player] or {}
			standing[player] = state
			local onSurface = isOnTreadmill(player)

			if not onSurface then
				-- Сошёл с полотна: снова можно приклеиваться
				state.MustLeave = false
				if player:GetAttribute("OnTreadmill") then
					SpeedService.LeaveTreadmill(player)
				end
			elseif player:GetAttribute("OnTreadmill") then
				local gain = SpeedService.GetTreadmillGain(player)
				if gain > 0 then
					EconomyService.AddSpeed(player, gain)
					popupEvent:FireClient(player, gain)
				end
			elseif not state.MustLeave and os.clock() >= (state.BlockedUntil or 0) then
				enterTreadmill(player)
			end
		end
	end
end

function SpeedService.Init()
	DataService.ProfileLoaded:Connect(onProfileLoaded)

	Players.PlayerRemoving:Connect(function(player)
		treadmills[player] = nil
		standing[player] = nil
		tracking[player] = nil
		walkSpeeds[player] = nil
	end)

	-- Игрок нажал прыжок, чтобы сойти с дорожки
	Remotes.Event("LeaveTreadmill").OnServerEvent:Connect(function(player)
		SpeedService.LeaveTreadmill(player, true)
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

	task.spawn(function()
		while true do
			task.wait(T.GainInterval)
			local ok, err = pcall(treadmillTick)
			if not ok then
				warn("[SpeedService] Ошибка в цикле дорожки: " .. tostring(err))
			end
		end
	end)
end

return SpeedService
