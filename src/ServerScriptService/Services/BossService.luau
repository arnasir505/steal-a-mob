-- BossService: боссы биомов.
--
-- Как ведёт себя босс:
--  * спит на своём месте. Просыпается, когда кто-то взял яйцо ЕГО биома —
--    на чужие яйца не реагирует;
--  * гонится за тем, у кого яйцо его биома реже. Если позже кто-то взял
--    яйцо ещё реже — переключается на него;
--  * бежит со своей постоянной скоростью: Speed из Config/Biomes переводится
--    в WalkSpeed той же формулой, что и стата игрока (Formulas.BossWalkSpeed).
--    Эффективная скорость игрока (стата x замедление от яйца) >= Speed босса —
--    игрок убежит, меньше — босс догонит;
--  * догнал в своём биоме — отбирает яйцо, кладёт туда, где оно появилось,
--    толкает игрока и идёт спать;
--  * догнал за пределами биома — только толкает и идёт спать. Яйцо остаётся
--    у игрока (настройка GameConfig.Boss.OutsideCatchDropsEgg). Если игрок
--    бросит яйцо и поднимет снова — босс снова проснётся;
--  * игрок донёс яйцо до safe zone или бросил его — босс идёт спать.
--  Урона нет, игроки не умирают.
--
-- Где игра ищет модель босса (имя — Boss.ModelName из Config/Biomes):
--   1. Внутри модели биома: Workspace.Biomes.Plains.Farmer (или модель с именем Boss).
--      Где она стоит в Studio, там босс и спит. Самый простой вариант.
--   2. ReplicatedStorage.Assets.Bosses.Farmer — тогда босс спит на детали
--      BossSpawn внутри биома (низ босса ставится на её центр),
--      а если её нет — в центре биома.
--   3. Ничего нет — строится временный босс из кубиков.
--
-- Какой может быть модель:
--   * обычная модель из деталей — игра сама добавит невидимую HumanoidRootPart
--     и Humanoid и скрепит все детали. Перёд босса — сторона Front у PrimaryPart.
--     Если босс бежит боком или спиной, поставь Boss.TurnDegrees = 90, -90 или 180;
--   * готовый риг (внутри есть Humanoid и HumanoidRootPart) — берётся как есть.
--     Анимации кладутся в риг по состояниям: папка (или StringValue) с именем
--     Sleep, Run или Walk, а в ней объекты Animation с любыми именами.
--     Если анимаций в папке несколько, каждый раз берётся случайная.
--     Можно и без папок: объект Animation с именем Sleep, Run или Walk.
--     Нет своей анимации или она не загрузилась (чужая, нет доступа) —
--     берётся стандартная анимация Roblox (GameConfig.Boss.DefaultAnimations).
--     Скрипт Animate внутри босса (стандартный скрипт Roblox) выключается:
--     он сам включает бег при любом движении и спорил бы с этими анимациями.
--
-- Босс проходит сквозь стены и игроков: у его деталей выключены столкновения,
-- а по земле он ходит за счёт Humanoid. Поэтому на препятствиях он не застревает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local EggService = require(script.Parent.EggService)
local SpeedService = require(script.Parent.SpeedService)
local WorldService = require(script.Parent.WorldService)
local RoundService = require(script.Parent.RoundService)
local PlotBuilder = require(script.Parent.PlotBuilder)

local C = GameConfig.Boss

local SLEEP_COLOR = Color3.fromRGB(170, 190, 255)
local ALERT_COLOR = Color3.fromRGB(255, 70, 60)

-- Имена анимаций внутри рига -> какое состояние они показывают
local ANIMATION_KEYS = { sleep = "Sleep", idle = "Sleep", run = "Run", walk = "Walk" }

-- Эти состояния Humanoid боссу не нужны: он не должен падать, садиться
-- на сиденья, лазить по лестницам и умирать
local DISABLED_STATES = {
	Enum.HumanoidStateType.Dead,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.PlatformStanding,
}

local BossService = {}

local bossFolder -- Workspace.Bosses
local bosses = {} -- по одному на биом

-- Запись босса:
-- {
--   Id          -- Id биома
--   Name        -- имя над головой
--   Config      -- Boss из Config/Biomes (Speed, Knockback, ...)
--   Template    -- готовая копия модели, чтобы пересоздать босса, если он пропал
--   Model, Root, Humanoid, Status (TextLabel)
--   BedPivot, BedPosition -- где спит
--   CatchRadius -- с какого расстояния ловит
--   State       -- "Sleep", "Wake", "Chase", "Return"
--   Target      -- за кем гонится
--   Ignored     -- [eggId] = true: яйца, с которыми босс уже "разобрался"
-- }

---------------------------------------------------------------------
-- Вспомогательное
---------------------------------------------------------------------

local function rootOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function isAlive(boss)
	return boss.Model ~= nil and boss.Model.Parent ~= nil
		and boss.Root ~= nil and boss.Root.Parent ~= nil
		and boss.Humanoid ~= nil and boss.Humanoid.Parent ~= nil
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function setStatus(boss, text, color)
	if boss.Status and boss.Status.Text ~= text then
		boss.Status.Text = text
		boss.Status.TextColor3 = color
	end
end

---------------------------------------------------------------------
-- Анимации: свои из рига, а если их нет или они не загрузились — стандартные Roblox
---------------------------------------------------------------------

local ANIMATION_STATES = { "Sleep", "Run", "Walk" }

-- Для какого состояния анимация: сначала смотрим на папку, в которой она лежит
-- (Animate.Run.RunAnim -> Run), потом на её собственное имя (Run -> Run)
local function animationKey(animation)
	local parent = animation.Parent
	return (parent and ANIMATION_KEYS[string.lower(parent.Name)])
		or ANIMATION_KEYS[string.lower(animation.Name)]
end

local function loadTrack(animator, animation)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		return track
	end
	return nil
end

-- Стандартная анимация Roblox для состояния. Только для рига с суставами:
-- модели из приваренных деталей двигать нечем.
local function loadDefaultTrack(boss, key)
	if not boss.Model:FindFirstChildWhichIsA("Motor6D", true) then
		return nil
	end
	local rig = boss.Humanoid.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
	local id = C.DefaultAnimations[rig] and C.DefaultAnimations[rig][key]
	if not id then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = loadTrack(boss.Animator, animation)
	animation:Destroy()
	return track
end

-- key = "Sleep", "Run", "Walk" или nil (остановить всё).
-- force = true — перезапустить, даже если это состояние уже играет.
local function playAnimation(boss, key, force)
	if boss.PlayingKey == key and not force then
		return
	end
	boss.PlayingKey = key
	if boss.PlayingTrack then
		boss.PlayingTrack:Stop(0.2)
		boss.PlayingTrack = nil
	end
	local list = key and boss.Tracks[key]
	if key == "Walk" and (not list or #list == 0) then
		list = boss.Tracks.Run -- нечем идти шагом — идёт с анимацией бега
	end
	if list and #list > 0 then
		local track = list[math.random(1, #list)]
		track:Play(0.2)
		boss.PlayingTrack = track
	end
end

-- Своя анимация может не загрузиться: например, она принадлежит чужому
-- аккаунту. LoadAnimation об этом не сообщает, но у такой дорожки длина так
-- и остаётся 0. Ждём немного и, если не загрузилась, ставим стандартную.
local function watchLoading(boss, key, track, source)
	local tracks = boss.Tracks
	task.spawn(function()
		local deadline = os.clock() + C.AnimationLoadTimeout
		while track.Length == 0 and os.clock() < deadline do
			task.wait(0.25)
		end
		-- Загрузилась, или босса уже пересоздали — делать нечего
		if track.Length > 0 or boss.Tracks ~= tracks then
			return
		end

		local list = tracks[key]
		local index = list and table.find(list, track)
		if index then
			table.remove(list, index)
		end
		track:Stop(0)
		track:Destroy()

		local replaced = "ничего"
		if not list or #list == 0 then
			local default = loadDefaultTrack(boss, key)
			if default then
				tracks[key] = { default }
				replaced = "стандартная анимация Roblox"
			end
		end
		warn("[BossService] " .. boss.Name .. ": анимация " .. source .. " не загрузилась"
			.. " (скорее всего, она чужая и у игры нет к ней доступа). Вместо неё: " .. replaced
			.. ". Удали её из модели или замени своей, чтобы не было ошибки в Output.")

		if boss.PlayingTrack == track then
			boss.PlayingTrack = nil
			playAnimation(boss, boss.PlayingKey, true)
		end
	end)
end

-- boss.Tracks[key] = список дорожек: в одной папке может быть несколько анимаций
local function loadAnimations(boss)
	boss.Tracks = {}
	boss.PlayingKey = nil
	boss.PlayingTrack = nil
	local animator = boss.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = boss.Humanoid
	end
	boss.Animator = animator
	-- Останавливаем всё, что успел включить кто-то другой (скрипт Animate)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end

	-- Свои анимации из рига
	local own = 0
	for _, animation in ipairs(boss.Model:GetDescendants()) do
		local key = animation:IsA("Animation") and animationKey(animation)
		if key then
			local track = loadTrack(animator, animation)
			if track then
				boss.Tracks[key] = boss.Tracks[key] or {}
				table.insert(boss.Tracks[key], track)
				own = own + 1
				watchLoading(boss, key, track, animation:GetFullName())
			end
		end
	end

	-- Чего нет — берём стандартное
	local defaults = {}
	for _, key in ipairs(ANIMATION_STATES) do
		if not boss.Tracks[key] then
			local track = loadDefaultTrack(boss, key)
			if track then
				boss.Tracks[key] = { track }
				table.insert(defaults, key)
			end
		end
	end
	print(string.format("[BossService] %s: своих анимаций %d, стандартные для: %s",
		boss.Name, own, #defaults > 0 and table.concat(defaults, ", ") or "нет"))
end

---------------------------------------------------------------------
-- Модель босса
---------------------------------------------------------------------

local function makeBlock(name, size, position, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.Parent = parent
	return part
end

-- Временный босс из кубиков, пока автор не сделал свою модель.
-- Смотрит в сторону -Z (туда же, куда Front у детали), там у него глаза.
local function buildTempBoss(name)
	local model = Instance.new("Model")
	model.Name = name
	local skin = Color3.fromRGB(225, 175, 135)
	local shirt = Color3.fromRGB(170, 55, 45)
	local pants = Color3.fromRGB(45, 70, 130)
	local straw = Color3.fromRGB(225, 195, 110)
	local black = Color3.fromRGB(20, 20, 20)

	makeBlock("LegL", Vector3.new(1.2, 3, 1.2), Vector3.new(-0.7, 1.5, 0), pants, model)
	makeBlock("LegR", Vector3.new(1.2, 3, 1.2), Vector3.new(0.7, 1.5, 0), pants, model)
	local body = makeBlock("Body", Vector3.new(2.8, 3, 1.6), Vector3.new(0, 4.5, 0), shirt, model)
	makeBlock("ArmL", Vector3.new(1, 3, 1), Vector3.new(-1.9, 4.5, 0), skin, model)
	makeBlock("ArmR", Vector3.new(1, 3, 1), Vector3.new(1.9, 4.5, 0), skin, model)
	makeBlock("HeadBlock", Vector3.new(1.8, 1.8, 1.8), Vector3.new(0, 6.9, 0), skin, model)
	makeBlock("EyeL", Vector3.new(0.3, 0.3, 0.1), Vector3.new(-0.4, 7.1, -0.95), black, model)
	makeBlock("EyeR", Vector3.new(0.3, 0.3, 0.1), Vector3.new(0.4, 7.1, -0.95), black, model)
	makeBlock("HatBrim", Vector3.new(3.4, 0.3, 3.4), Vector3.new(0, 7.95, 0), straw, model)
	makeBlock("HatTop", Vector3.new(2, 0.9, 2), Vector3.new(0, 8.55, 0), straw, model)

	model.PrimaryPart = body
	model:ScaleTo(1.6) -- босс крупнее игрока
	return model
end

-- Ищет модель босса. Возвращает модель и true, если она стоит прямо в биоме.
local function findBossModel(biome)
	local name = biome.Config.Boss.ModelName or "Boss"
	for _, candidate in ipairs({ name, "Boss" }) do
		local found = biome.Model:FindFirstChild(candidate, true)
		if found and found:IsA("Model") then
			return found, true
		end
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Bosses")
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template:Clone(), false
	end
	return nil, false
end

-- Где спит босс, если его модель лежит не в биоме: деталь BossSpawn или центр биома
local function bedFor(biome)
	local marker = biome.Model:FindFirstChild("BossSpawn", true)
	if marker and marker:IsA("BasePart") then
		-- Это просто метка: прячем её, чтобы на неё не падали яйца и не спотыкались игроки
		marker.Transparency = 1
		marker.CanCollide = false
		marker.CanQuery = false
		local _, yaw = marker.CFrame:ToOrientation()
		return marker.Position, yaw
	end
	local box = biome.Boxes[1]
	local top = (box.CFrame * CFrame.new(0, box.Size.Y / 2, 0)).Position
	local ground = WorldService.FindGround(top, nil, box.Size.Y + GameConfig.Egg.SpawnHeightAbove)
	return ground or box.CFrame.Position, 0
end

-- Превращает модель в "ходячую": корневая деталь, Humanoid, всё скреплено.
-- Модель уже лежит в Workspace и заякорена.
local function prepareModel(model, turnDegrees)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local isRig = humanoid ~= nil and root ~= nil and root:IsA("BasePart")

	if not isRig then
		if humanoid then
			humanoid:Destroy()
		end
		if root then
			root.Name = "OldRootPart" -- деталь с таким именем, но это не риг
		end
		-- Невидимая корневая деталь в центре модели. Humanoid держит её низ
		-- на высоте HipHeight над землёй — ровно так, чтобы ноги стояли на полу.
		local boxCFrame, boxSize = model:GetBoundingBox()
		local _, yaw = boxCFrame:ToOrientation()
		root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Transparency = 1
		root.Anchored = true
		root.Size = Vector3.new(
			math.max(1, boxSize.X * 0.5),
			math.max(1, boxSize.Y * 0.5),
			math.max(1, boxSize.Z * 0.5)
		)
		root.CFrame = CFrame.new(boxCFrame.Position) * CFrame.Angles(0, yaw + math.rad(turnDegrees or 0), 0)
		root.Parent = model

		humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15 -- у R15 HipHeight считается от низа корня
		humanoid.HipHeight = boxSize.Y / 2 - root.Size.Y / 2
		humanoid.Parent = model
	end

	-- Стандартный скрипт Animate сам включает бег, как только Humanoid двигается,
	-- и спорил бы с нашими анимациями. Анимации берём из его папок, а сам скрипт выключаем.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") and descendant.Name == "Animate" then
			descendant.Enabled = false
		end
	end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false -- сквозь игроков и стены
			part.CanTouch = false
			part.CanQuery = false   -- лучи (поиск пола для яиц) босса не видят
			if part ~= root then
				part.Massless = true
				-- У рига детали уже соединены суставами — привариваем только
				-- те, что ни к чему не прикреплены. Обычную модель — целиком.
				if not isRig or #part:GetJoints() == 0 then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = part
					weld.Parent = root
				end
				part.Anchored = false
			end
		end
	end
	root.Anchored = true -- пока спит, стоит заякоренный
	model.PrimaryPart = root
	return root, humanoid
end

-- Табличка над головой: имя и что босс сейчас делает
local function makeLabel(model, root, name)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local above = (boxCFrame.Position.Y + boxSize.Y / 2) - root.Position.Y + 2

	local gui = Instance.new("BillboardGui")
	gui.Name = "BossLabel"
	gui.Size = UDim2.fromScale(10, 3)
	gui.StudsOffsetWorldSpace = Vector3.new(0, above, 0)
	gui.MaxDistance = 250
	gui.LightInfluence = 0
	gui.Adornee = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.55)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.2
	title.Text = name
	title.Parent = gui

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromScale(0, 0.55)
	status.Size = UDim2.fromScale(1, 0.45)
	status.Font = Enum.Font.GothamBold
	status.TextScaled = true
	status.TextColor3 = SLEEP_COLOR
	status.TextStrokeTransparency = 0.2
	status.Text = "Zzz"
	status.Parent = gui

	gui.Parent = root
end

-- Привязывает запись босса к модели (при запуске и после пересоздания)
local function bind(boss, model)
	boss.Model = model
	boss.Root = model:FindFirstChild("HumanoidRootPart")
	boss.Humanoid = model:FindFirstChildOfClass("Humanoid")
	local gui = boss.Root:FindFirstChild("BossLabel")
	boss.Status = gui and gui:FindFirstChild("Status")

	-- Эти настройки не копируются вместе с моделью, поэтому ставим их каждый раз
	local humanoid = boss.Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoJumpEnabled = false
	for _, state in ipairs(DISABLED_STATES) do
		humanoid:SetStateEnabled(state, false)
	end
	loadAnimations(boss)
end

---------------------------------------------------------------------
-- Состояния: спит -> просыпается -> гонится -> идёт домой -> спит
---------------------------------------------------------------------

local function sleep(boss)
	boss.State = "Sleep"
	boss.Target = nil
	boss.Humanoid:MoveTo(boss.Root.Position)
	boss.Root.Anchored = true
	boss.Model:PivotTo(boss.BedPivot)
	setStatus(boss, "Zzz", SLEEP_COLOR)
	playAnimation(boss, "Sleep")
end

-- Снимает якорь. Физику босса считает сервер, а не компьютер ближайшего
-- игрока — иначе читер мог бы двигать босса как захочет.
local function unfreeze(boss)
	if boss.Root.Anchored then
		boss.Root.Anchored = false
		pcall(function()
			boss.Root:SetNetworkOwner(nil)
		end)
		boss.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
end

local function wake(boss, now)
	unfreeze(boss)
	boss.State = "Wake"
	boss.WakeUntil = now + C.WakeUpTime
	setStatus(boss, "!", ALERT_COLOR)
	playAnimation(boss, nil)
end

local function startChase(boss)
	unfreeze(boss)
	boss.State = "Chase"
	playAnimation(boss, "Run")
end

-- Постоянная скорость босса в погоне
local function chaseWalkSpeed(boss)
	return Formulas.BossWalkSpeed(boss.Config.Speed or 1)
end

-- Домой идёт шагом
local function returnWalkSpeed(boss)
	return chaseWalkSpeed(boss) * C.ReturnSpeedShare
end

local function goHome(boss, now)
	boss.State = "Return"
	boss.Target = nil
	boss.ReturnStartedAt = now
	boss.Humanoid.WalkSpeed = returnWalkSpeed(boss)
	boss.Humanoid:MoveTo(boss.BedPosition)
	setStatus(boss, "...", SLEEP_COLOR)
	playAnimation(boss, "Walk")
end

local function walkHome(boss, now)
	local arrived = flatDistance(boss.Root.Position, boss.BedPosition) <= 3
	local stuck = now - boss.ReturnStartedAt > C.ReturnTimeout
	if arrived or stuck then
		sleep(boss)
		return
	end
	-- MoveTo сам сдаётся через 8 секунд, поэтому повторяем
	boss.Humanoid.WalkSpeed = returnWalkSpeed(boss)
	boss.Humanoid:MoveTo(boss.BedPosition)
end

---------------------------------------------------------------------
-- Погоня
---------------------------------------------------------------------

-- Кого ловить: из тех, кто несёт яйцо ЭТОГО биома (и не в safe zone).
-- Сначала самое редкое яйцо; при равной редкости — текущая цель,
-- чтобы босс не метался; потом ближайший.
local function pickTarget(boss)
	local best, bestRank, bestDistance, bestIsCurrent
	for _, player in ipairs(Players:GetPlayers()) do
		local egg = EggService.GetCarried(player)
		local root = egg and egg.BiomeId == boss.Id and not boss.Ignored[egg.Id] and rootOf(player)
		if root and not WorldService.IsInSafeZone(root.Position) then
			local rank = Rarities.GetRank(egg.Item.Rarity)
			local distance = (root.Position - boss.Root.Position).Magnitude
			local isCurrent = player == boss.Target
			local better
			if not best then
				better = true
			elseif rank ~= bestRank then
				better = rank > bestRank
			elseif isCurrent ~= bestIsCurrent then
				better = isCurrent
			else
				better = distance < bestDistance
			end
			if better then
				best, bestRank, bestDistance, bestIsCurrent = player, rank, distance, isCurrent
			end
		end
	end
	return best
end

local function chase(boss, player, root)
	boss.Humanoid.WalkSpeed = chaseWalkSpeed(boss)
	boss.Humanoid:MoveTo(root.Position)
	setStatus(boss, "Chasing " .. player.DisplayName, ALERT_COLOR)
end

local function isCaught(boss, root)
	local offset = root.Position - boss.Root.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= boss.CatchRadius
		and math.abs(offset.Y) <= C.CatchHeight
end

local function catch(boss, player, root, now)
	local egg = EggService.GetCarried(player)
	if not egg or egg.BiomeId ~= boss.Id or WorldService.IsInSafeZone(root.Position) then
		return
	end

	local biome = WorldService.GetBiomeAt(root.Position)
	if biome and biome.Id == boss.Id then
		-- В своём биоме: отбирает яйцо и кладёт на место
		EggService.ReturnToSpawn(player)
		Remotes.Notify(player, "Caught!", boss.Name .. " took the egg back.")
	elseif C.OutsideCatchDropsEgg then
		EggService.Drop(player, root.Position)
		Remotes.Notify(player, "Caught!", boss.Name .. " knocked the egg out of your hands.")
	else
		-- За пределами биома: только толкает, яйцо остаётся у игрока.
		-- С этим яйцом босс больше не связывается, пока его не поднимут заново.
		boss.Ignored[egg.Id] = true
		Remotes.Notify(player, "Pushed!", boss.Name .. " gave up. Run to the safe zone!")
	end

	SpeedService.Knockback(player, boss.Root.Position, boss.Config.Knockback or 60)
	goHome(boss, now)
end

---------------------------------------------------------------------
-- Циклы
---------------------------------------------------------------------

local function respawn(boss)
	if boss.Model then
		boss.Model:Destroy()
	end
	local model = boss.Template:Clone()
	model.Parent = bossFolder
	bind(boss, model)
	sleep(boss)
end

-- Раз в TickInterval: кого ловить и куда бежать
local function update(boss, now)
	if not isAlive(boss) then
		if boss.Template then
			respawn(boss)
		end
		return
	end
	-- Провалился под карту — на место (иначе Roblox удалит модель)
	if boss.Root.Position.Y < boss.BedPosition.Y - C.FallLimit then
		sleep(boss)
		return
	end

	local target = pickTarget(boss)
	if not target then
		if boss.State == "Wake" then
			sleep(boss) -- ещё не сошёл с места
		elseif boss.State == "Chase" then
			goHome(boss, now)
		elseif boss.State == "Return" then
			walkHome(boss, now)
		end
		return
	end

	if target ~= boss.Target then
		boss.Target = target
		Remotes.Notify(target, boss.Name .. " is after you!", "Run to the safe zone!")
	end

	if boss.State == "Sleep" then
		wake(boss, now)
	elseif boss.State == "Return" then
		startChase(boss) -- уже на ногах, сразу в погоню
	elseif boss.State == "Wake" and now >= boss.WakeUntil then
		startChase(boss)
	end

	if boss.State == "Chase" then
		local root = rootOf(target)
		if root then
			chase(boss, target, root)
		end
	end
end

-- Каждый кадр: не догнал ли. На большой скорости за 0.1 секунды босс
-- пробегает десятки студов, поэтому проверять реже нельзя.
local function checkCatches()
	local now = os.clock()
	for _, boss in ipairs(bosses) do
		if boss.State == "Chase" and boss.Target and isAlive(boss) then
			local root = rootOf(boss.Target)
			if root and isCaught(boss, root) then
				catch(boss, boss.Target, root, now)
			end
		end
	end
end

---------------------------------------------------------------------
-- Запуск
---------------------------------------------------------------------

local function setupBoss(biome)
	local config = biome.Config.Boss
	local name = config.DisplayName or config.ModelName or "Boss"

	local model, inBiome = findBossModel(biome)
	if not model then
		model = buildTempBoss(config.ModelName or name)
		warn("[BossService] Нет модели босса " .. tostring(config.ModelName) .. " для биома " .. biome.Id
			.. " — построен временный. Положи свою модель в Workspace.Biomes." .. biome.Model.Name
			.. " (или в ReplicatedStorage.Assets.Bosses)")
	end

	-- Пока настраиваем, всё заякорено, чтобы ничего не упало
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	model.Parent = bossFolder
	if not inBiome then
		local position, yaw = bedFor(biome)
		PlotBuilder.PlaceOnGround(model, position, yaw)
	end

	local root = prepareModel(model, config.TurnDegrees)
	makeLabel(model, root, name)

	local _, size = model:GetBoundingBox()
	local boss = {
		Id = biome.Id,
		Name = name,
		Config = config,
		BedPivot = model:GetPivot(),
		BedPosition = root.Position,
		CatchRadius = C.CatchDistance + math.max(size.X, size.Z) / 2,
		State = "Sleep",
		Ignored = {},
		Template = model:Clone(),
	}
	if not boss.Template then
		warn("[BossService] Модель босса " .. name .. " нельзя копировать (Archivable = false)."
			.. " Если босс пропадёт, он не появится снова.")
	end
	bind(boss, model)
	sleep(boss)
	table.insert(bosses, boss)
end

-- Все боссы на место и спать (новый раунд, тестовая команда)
function BossService.ResetAll()
	for _, boss in ipairs(bosses) do
		boss.Ignored = {}
		if isAlive(boss) then
			sleep(boss)
		elseif boss.Template then
			respawn(boss)
		end
	end
end

-- Строки для тестовой команды !boss
function BossService.DebugLines(player)
	local lines = {}
	for _, boss in ipairs(bosses) do
		table.insert(lines, string.format(
			"%s (%s): %s, цель: %s, скорость %s (WalkSpeed в погоне %.1f, домой %.1f), ловит с %.1f студов",
			boss.Name, boss.Id, boss.State,
			boss.Target and boss.Target.Name or "нет",
			tostring(boss.Config.Speed), chaseWalkSpeed(boss), returnWalkSpeed(boss), boss.CatchRadius))
		if player then
			local mine = SpeedService.GetEffectiveSpeed(player)
			table.insert(lines, string.format("  твоя эффективная скорость %.1f (WalkSpeed %.1f) -> %s",
				mine, SpeedService.GetWalkSpeed(player),
				mine >= (boss.Config.Speed or 1) and "убежишь" or "догонит"))
		end
	end
	if #lines == 0 then
		table.insert(lines, "боссов нет")
	end
	return lines
end

function BossService.Init()
	bossFolder = workspace:FindFirstChild("Bosses")
	if not bossFolder then
		bossFolder = Instance.new("Folder")
		bossFolder.Name = "Bosses"
		bossFolder.Parent = workspace
	end

	for _, biome in ipairs(WorldService.GetBiomes()) do
		if biome.Config.Boss then
			local ok, err = pcall(setupBoss, biome)
			if not ok then
				warn("[BossService] Не удалось создать босса биома " .. biome.Id .. ": " .. tostring(err))
			end
		end
	end

	-- Яйцо подняли заново — босс снова за него возьмётся
	EggService.EggTaken:Connect(function(_, biomeId, _, eggId)
		for _, boss in ipairs(bosses) do
			if boss.Id == biomeId and eggId then
				boss.Ignored[eggId] = nil
			end
		end
	end)

	RoundService.RoundStarted:Connect(BossService.ResetAll)

	task.spawn(function()
		while true do
			task.wait(C.TickInterval)
			local now = os.clock()
			for _, boss in ipairs(bosses) do
				local ok, err = pcall(update, boss, now)
				if not ok then
					warn("[BossService] Ошибка босса " .. boss.Id .. ": " .. tostring(err))
				end
			end
		end
	end)

	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(checkCatches)
		if not ok then
			warn("[BossService] Ошибка проверки поимки: " .. tostring(err))
		end
	end)

	print("[BossService] Боссов: " .. #bosses)
end

return BossService
