-- BossFx: анимации и эффекты боссов (только картинка, на игру не влияет).
--
-- Модели из BossModels (атрибут BossRig) двигаются кодом: каждый кадр клиент
-- поворачивает суставы Motor6D по состоянию босса (атрибут BossState от сервера):
--   Sleep  — дремлет стоя, голова свесилась, над головой «Z»
--   Wake   — вскакивает и рычит (руки вверх, ударная волна)
--   Chase  — бег, у каждого босса свой (фараон тянет руки вперёд, йети бежит
--            вразвалку, отшельник горбится, голем топает)
--   Return — идёт шагом,  Carry — несёт яйцо над головой
-- Разовые события от сервера (Remotes "BossFx"): "Wake" — рык, "Hit" — удар:
-- замах оружием, волна и блоки-осколки у игрока, у самого игрока трясётся камера.
--
-- Своя модель автора (без BossRig) суставами не двигается — у неё свои анимации,
-- но пыль из-под ног, волны и тряска работают и для неё.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local player = Players.LocalPlayer

local ANIMATE_DISTANCE = 450 -- дальше камеры босс не анимируется (не видно, а кадры тратятся)
local FX_DISTANCE = 250      -- дальше не показываются частицы, «Z» и шаги
local MAX_DEBRIS = 220       -- сколько блоков-осколков одновременно на всю игру
local TAU = math.pi * 2

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

---------------------------------------------------------------------
-- Стили боссов
---------------------------------------------------------------------
-- RunLegs/RunArms — размах ног и рук на бегу (радианы), Lean — наклон вперёд на бегу,
-- Hunch — постоянная сутулость, Bob — подпрыгивание (в пикселях модели),
-- Cadence — самый частый шаг (шагов-пар в секунду), Weapon — в правой руке оружие
-- (рука чуть вперёд, на бегу почти не машет), ArmsForward — руки вытянуты вперёд,
-- Smash — бьёт двумя руками сверху, Heavy — тяжёлые шаги (волна и больше осколков),
-- Dust — цвета блоков из-под ног, Ring — цвет ударной волны, Aura — постоянные частицы.
local STYLES = {
	Default = {
		RunLegs = 0.9, RunArms = 0.8, Lean = 0.18, Hunch = 0, Bob = 1, Cadence = 2.6,
		Dust = { rgb(134, 96, 67), rgb(106, 164, 62) }, Ring = rgb(255, 230, 160),
	},
	Farmer = {
		RunLegs = 0.95, RunArms = 0.85, Lean = 0.2, Hunch = 0, Bob = 1, Cadence = 2.8, Weapon = 0.55,
		Dust = { rgb(134, 96, 67), rgb(220, 190, 80), rgb(106, 164, 62) }, Ring = rgb(255, 225, 140),
	},
	Lumberjack = {
		RunLegs = 0.9, RunArms = 0.8, Lean = 0.22, Hunch = 0, Bob = 1.2, Cadence = 2.5, Weapon = 0.9,
		Dust = { rgb(120, 88, 52), rgb(60, 120, 44), rgb(160, 120, 70) }, Ring = rgb(170, 230, 120),
	},
	Pharaoh = {
		RunLegs = 0.8, RunArms = 0.15, Lean = 0.1, Hunch = 0, Bob = 0.6, Cadence = 2.4, ArmsForward = 1.45,
		Dust = { rgb(219, 207, 160), rgb(205, 188, 132), rgb(232, 184, 52) }, Ring = rgb(80, 240, 255),
		Aura = "Sand",
	},
	Yeti = {
		RunLegs = 0.8, RunArms = 1.25, Lean = 0.45, Hunch = 0.1, Bob = 2, Cadence = 2.1, Smash = true, Heavy = true,
		Dust = { rgb(245, 250, 252), rgb(200, 225, 245), rgb(150, 190, 240) }, Ring = rgb(200, 235, 255),
		Aura = "Snow",
	},
	BogHermit = {
		RunLegs = 0.75, RunArms = 0.35, Lean = 0.25, Hunch = 0.35, Bob = 0.8, Cadence = 3, Weapon = 0.7,
		Dust = { rgb(92, 72, 56), rgb(88, 104, 52), rgb(140, 255, 90) }, Ring = rgb(140, 255, 90),
		Aura = "Bubbles",
	},
	InfernoKing = {
		RunLegs = 0.85, RunArms = 0.6, Lean = 0.2, Hunch = 0, Bob = 1.2, Cadence = 2.3, Weapon = 0.6, Heavy = true,
		Dust = { rgb(70, 64, 64), rgb(255, 110, 20), rgb(255, 180, 40) }, Ring = rgb(255, 120, 30),
		Aura = "Embers",
	},
	GemWarden = {
		RunLegs = 0.7, RunArms = 0.7, Lean = 0.28, Hunch = 0.05, Bob = 2.2, Cadence = 1.8, Smash = true, Heavy = true,
		Dust = { rgb(88, 70, 120), rgb(90, 230, 255), rgb(170, 100, 255), rgb(255, 110, 200) }, Ring = rgb(170, 100, 255),
		Aura = "Sparkles",
	},
}

---------------------------------------------------------------------
-- Блоки-осколки: маленькие кубики летят, падают на землю и тают
---------------------------------------------------------------------

local fxFolder = Instance.new("Folder")
fxFolder.Name = "BossFx"
fxFolder.Parent = workspace

local debris = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

-- Высота земли под точкой (без боссов, игроков и эффектов)
local function groundBelow(position)
	local ignore = { fxFolder }
	local bosses = workspace:FindFirstChild("Bosses")
	if bosses then
		table.insert(ignore, bosses)
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), rayParams)
	return result and result.Position.Y or position.Y
end

local function burst(position, colors, count, power, size)
	local ground = groundBelow(position)
	for _ = 1, count do
		if #debris >= MAX_DEBRIS then
			return
		end
		local s = size * (0.6 + math.random() * 0.8)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = colors[math.random(1, #colors)]
		part.Size = Vector3.new(s, s, s)
		part.CFrame = CFrame.new(position + Vector3.new((math.random() - 0.5) * size * 2, s, (math.random() - 0.5) * size * 2))
		part.Parent = fxFolder
		local angle = math.random() * TAU
		local out = power * (0.4 + math.random() * 0.8)
		table.insert(debris, {
			Part = part,
			Velocity = Vector3.new(math.cos(angle) * out, power * (0.8 + math.random() * 0.8), math.sin(angle) * out),
			Spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12,
			Life = 0,
			MaxLife = 0.9 + math.random() * 0.5,
			Ground = ground + s / 2,
			Size = s,
		})
	end
end

local function updateDebris(dt)
	for i = #debris, 1, -1 do
		local d = debris[i]
		d.Life += dt
		if d.Life >= d.MaxLife or not d.Part.Parent then
			d.Part:Destroy()
			table.remove(debris, i)
		else
			d.Velocity += Vector3.new(0, -workspace.Gravity * 0.6 * dt, 0)
			local p = d.Part.Position + d.Velocity * dt
			if p.Y < d.Ground then
				-- Ударился о землю: отскок слабее и трение
				p = Vector3.new(p.X, d.Ground, p.Z)
				d.Velocity = Vector3.new(d.Velocity.X * 0.5, -d.Velocity.Y * 0.3, d.Velocity.Z * 0.5)
				d.Spin *= 0.5
			end
			local fade = math.clamp((d.Life - d.MaxLife * 0.6) / (d.MaxLife * 0.4), 0, 1)
			local s = d.Size * (1 - fade * 0.8)
			d.Part.Size = Vector3.new(s, s, s)
			d.Part.CFrame = CFrame.new(p) * d.Part.CFrame.Rotation
				* CFrame.Angles(d.Spin.X * dt, d.Spin.Y * dt, d.Spin.Z * dt)
		end
	end
end

-- Ударная волна: светящееся кольцо по земле
local function ring(position, color, radius, time)
	local ground = groundBelow(position)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.25
	part.Size = Vector3.new(0.3, 2, 2)
	part.CFrame = CFrame.new(position.X, ground + 0.3, position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	part.Parent = fxFolder
	local tween = TweenService:Create(part, TweenInfo.new(time or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

-- Вспышка удара: светящийся кубик быстро раздувается и гаснет
local function flash(position, color, size)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * TAU, math.random() * TAU, 0)
	part.Parent = fxFolder
	local tween = TweenService:Create(part, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size, size, size),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

---------------------------------------------------------------------
-- Тряска камеры
---------------------------------------------------------------------

local shakeUntil, shakeTime, shakePower = 0, 0, 0

local function shake(power, time)
	local now = os.clock()
	if now + time > shakeUntil or power > shakePower then
		shakeUntil, shakeTime, shakePower = now + time, time, power
	end
end

RunService:BindToRenderStep("BossShake", Enum.RenderPriority.Camera.Value + 1, function()
	local left = shakeUntil - os.clock()
	if left <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local k = (left / shakeTime) * shakePower
	camera.CFrame *= CFrame.new((math.random() - 0.5) * k * 0.6, (math.random() - 0.5) * k * 0.6, 0)
		* CFrame.Angles((math.random() - 0.5) * k * 0.03, (math.random() - 0.5) * k * 0.03, 0)
end)

local function cameraDistance(position)
	return (workspace.CurrentCamera.CFrame.Position - position).Magnitude
end

---------------------------------------------------------------------
-- Звуки на клиенте (шаги — их слишком много, чтобы слать с сервера)
---------------------------------------------------------------------

local function makeSound(parent, name)
	local resolved = Sounds.Resolve(name)
	if not resolved then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = resolved.SoundId
	sound.Volume = resolved.Volume
	sound.PlaybackSpeed = resolved.Pitch
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 120
	sound.Parent = parent
	return sound
end

---------------------------------------------------------------------
-- Постоянные частицы (аура)
---------------------------------------------------------------------

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, value in pairs(props) do
		e[k] = value
	end
	e.Parent = parent
	return e
end

local function seq(a, b)
	return ColorSequence.new(a, b or a)
end

local function numbers(a, b)
	return NumberSequence.new(a, b or a)
end

-- Частицы, которые есть всегда. Run — пыль из-под ног, включается только на бегу.
local function makeAura(rig)
	local style, root, px = rig.Style, rig.Root, rig.Px
	local scale = px / 0.35
	local feet = Instance.new("Attachment")
	feet.Name = "BossFeet"
	feet.Position = Vector3.new(0, -(root.Size.Y / 2 + rig.HipHeight) + 0.3, 0)
	feet.Parent = root
	rig.Feet = feet
	rig.RunDust = emitter(feet, {
		Texture = SMOKE, Color = seq(style.Dust[1], style.Dust[2]), Rate = 0, Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5 * scale), NumberSequenceKeypoint.new(1, 4 * scale) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Drag = 3, LockedToPart = false,
	})

	local aura = style.Aura
	local body = rig.Model:FindFirstChild("Torso") or root
	if aura == "Snow" then
		emitter(body, {
			Texture = SPARKLE, Color = seq(rgb(255, 255, 255)), Rate = 8, Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -4, 0),
			Size = numbers(0.5 * scale), LightEmission = 0.3,
		})
	elseif aura == "Bubbles" then
		local jar = rig.Model:FindFirstChild("Jar", true) or body
		emitter(jar, {
			Texture = SPARKLE, Color = seq(rgb(140, 255, 90), rgb(60, 140, 40)), Rate = 6, Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, 2, 0), Size = numbers(0.6 * scale, 0.1), LightEmission = 0.6,
		})
	elseif aura == "Embers" then
		emitter(body, {
			Texture = SPARKLE, Color = seq(rgb(255, 160, 40), rgb(255, 60, 20)), Rate = 18, Lifetime = NumberRange.new(1, 2),
			Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 6, 0),
			Size = numbers(0.5 * scale, 0.05), LightEmission = 1,
		})
	elseif aura == "Sparkles" then
		emitter(body, {
			Texture = SPARKLE, Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(90, 230, 255)), ColorSequenceKeypoint.new(0.5, rgb(170, 100, 255)),
				ColorSequenceKeypoint.new(1, rgb(255, 110, 200)),
			}), Rate = 10, Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(180, 180), Size = numbers(0.7 * scale, 0.05), LightEmission = 1,
		})
	elseif aura == "Sand" then
		rig.SandSwirl = emitter(feet, {
			Texture = SMOKE, Color = seq(rgb(225, 210, 160)), Rate = 0, Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(80, 80), EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2 * scale), NumberSequenceKeypoint.new(1, 6 * scale) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
			RotSpeed = NumberRange.new(-90, 90), Drag = 2,
		})
	end
end

---------------------------------------------------------------------
-- Боссы на карте
---------------------------------------------------------------------

local JOINTS = { "RootJoint", "Neck", "LeftShoulder", "RightShoulder", "LeftHip", "RightHip" }
local rigs = {} -- [model] = запись

local function setup(model)
	if rigs[model] or not model:IsA("Model") then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local styleName = model:GetAttribute("BossRig")
	local rig = {
		Model = model,
		Root = root,
		Name = styleName or model.Name,
		Style = STYLES[styleName or ""] or STYLES.Default,
		Px = model:GetAttribute("RigPx") or 0.35,
		LegLength = model:GetAttribute("LegLength") or humanoid.HipHeight,
		HipHeight = humanoid.HipHeight,
		Joints = {},
		Current = {},
		Phase = 0,
		RunBlend = 0,
		LastSin = 0,
		LastStep = 0,
		LastZ = 0,
		LastPosition = root.Position,
		Speed = 0,
		HitStart = -10,
		WakeStart = -10,
	}
	if styleName then
		for _, name in ipairs(JOINTS) do
			local joint = model:FindFirstChild(name, true)
			if joint and joint:IsA("Motor6D") then
				rig.Joints[name] = joint
				rig.Current[name] = CFrame.identity
			end
		end
	end
	rig.StepSound = makeSound(root, Sounds.BossKey(rig.Name, "Step"))
	makeAura(rig)
	rigs[model] = rig
end

local function remove(model)
	local rig = rigs[model]
	if rig then
		rigs[model] = nil
		if rig.Feet then
			rig.Feet:Destroy()
		end
	end
end

-- «Z» над головой спящего босса: всплывает и тает
local function sleepZ(rig)
	local head = rig.Model:FindFirstChild("Head") or rig.Root
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(2, 2) * (rig.Px / 0.35)
	gui.LightInfluence = 0
	gui.StudsOffsetWorldSpace = Vector3.new(1.5, 2, 0)
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "Z"
	label.TextColor3 = rgb(200, 215, 255)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = fxFolder
	local time = 2.2
	TweenService:Create(gui, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(3.5, 7, 0),
	}):Play()
	local fade = TweenService:Create(label, TweenInfo.new(time), { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade:Play()
	fade.Completed:Connect(function()
		gui:Destroy()
	end)
end

local function footStep(rig, left)
	local style = rig.Style
	local leg = rig.Model:FindFirstChild(left and "LeftLeg" or "RightLeg")
	local position = leg and (leg.Position - Vector3.new(0, leg.Size.Y / 2, 0))
		or (rig.Root.Position - Vector3.new(0, rig.Root.Size.Y / 2 + rig.HipHeight, 0))
	local scale = rig.Px / 0.35
	burst(position, style.Dust, style.Heavy and 6 or 3, 10 * scale, 0.5 * scale)
	if style.Heavy then
		ring(position, style.Dust[1], 6 * scale, 0.35)
	end
	if rig.StepSound then
		rig.StepSound.TimePosition = 0
		rig.StepSound:Play()
	end
end

---------------------------------------------------------------------
-- Позы
---------------------------------------------------------------------

local function angles(x, y, z)
	return CFrame.Angles(x or 0, y or 0, z or 0)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Целевые повороты суставов на этот кадр
local function pose(rig, state, now, dt)
	local style = rig.Style
	local px = rig.Px
	local target = {}

	-- Скорость по сдвигу за кадр: так видно и то, что двигает сервер
	local position = rig.Root.Position
	local moved = Vector3.new(position.X - rig.LastPosition.X, 0, position.Z - rig.LastPosition.Z).Magnitude
	rig.LastPosition = position
	local speed = dt > 0 and moved / dt or 0
	rig.Speed = lerp(rig.Speed, speed, math.min(1, dt * 10))
	local moving = rig.Speed > 1 and state ~= "Sleep"
	rig.RunBlend = lerp(rig.RunBlend, moving and 1 or 0, math.min(1, dt * 8))
	local blend = rig.RunBlend

	local walking = state == "Return" or state == "Carry"
	local amp = walking and 0.55 or 1
	local cadence = math.clamp(rig.Speed / math.max(1, rig.LegLength * 3.2), 0, walking and 1.4 or style.Cadence)
	rig.Phase = (rig.Phase + dt * cadence * TAU) % (TAU * 1000)
	local s, c = math.sin(rig.Phase), math.cos(rig.Phase)

	-- Шаги: каждый раз, когда нога проходит низ
	if moving and blend > 0.5 and rig.Speed > 4 and (s >= 0) ~= (rig.LastSin >= 0)
		and now - rig.LastStep > 0.12 and cameraDistance(position) < FX_DISTANCE then
		rig.LastStep = now
		footStep(rig, s >= 0)
	end
	rig.LastSin = s

	local legSwing = s * style.RunLegs * amp * blend
	local armSwing = -s * style.RunArms * amp * blend
	local leftArm, rightArm = armSwing, -armSwing
	local leftRoll, rightRoll = 0, 0
	if style.ArmsForward then
		leftArm = style.ArmsForward + armSwing * 0.3
		rightArm = style.ArmsForward - armSwing * 0.3
	end
	if style.Weapon and not style.ArmsForward then
		rightArm = style.Weapon + rightArm * 0.35
	end
	local lean = -(style.Lean * blend * amp + style.Hunch)
	local bob = math.abs(c) * style.Bob * px * blend * amp
	local twist = s * 0.08 * blend
	local headPitch = -lean * 0.6
	local rootDown = 0
	local leftLeg, rightLeg = legSwing, -legSwing
	local legRoll = 0

	if state == "Sleep" then
		-- Дремлет стоя: голова свесилась, руки висят, медленно покачивается и дышит.
		-- Ноги на месте — так модель не уходит под пол.
		local breath = math.sin(now * 1.3)
		leftLeg, rightLeg = 0, 0
		legRoll = 0.04
		leftArm, rightArm = 0.12 + breath * 0.03, 0.12 + breath * 0.03
		leftRoll, rightRoll = -0.06, 0.06
		lean = -0.12 - style.Hunch - breath * 0.02
		headPitch = -0.55 + math.sin(now * 0.6) * 0.08
		bob = breath * 0.15 * px
		twist = math.sin(now * 0.4) * 0.04
	elseif state == "Carry" then
		-- Яйцо над головой: обе руки вверх
		leftArm, rightArm = 2.9, 2.9
		leftRoll, rightRoll = 0.15, -0.15
		headPitch = 0.1
	end

	-- Рык после пробуждения
	local sinceWake = now - rig.WakeStart
	if sinceWake < 1 then
		local k = math.sin(math.clamp(sinceWake / 1, 0, 1) * math.pi)
		leftArm = lerp(leftArm, 2.4, k)
		rightArm = lerp(rightArm, 2.4, k)
		leftRoll = lerp(leftRoll, -0.6, k)
		rightRoll = lerp(rightRoll, 0.6, k)
		headPitch = lerp(headPitch, 0.5, k)
		lean = lerp(lean, 0.15, k)
		rootDown = 0
		leftLeg, rightLeg, legRoll = lerp(leftLeg, 0, k), lerp(rightLeg, 0, k), lerp(legRoll, 0.15, k)
	end

	-- Удар: замах вверх и резко вниз
	local sinceHit = now - rig.HitStart
	if sinceHit < 0.55 then
		local u = sinceHit / 0.55
		local swing
		if u < 0.4 then
			swing = 3 * (u / 0.4)
			lean = 0.2
		else
			swing = 3 - 3.4 * math.min(1, (u - 0.4) / 0.2)
			lean = -0.4
		end
		rightArm, rightRoll = swing, 0
		if style.Smash then
			leftArm, leftRoll = swing, 0
		end
		headPitch = lean * -0.5
	end

	target.RootJoint = CFrame.new(0, bob - rootDown, 0) * angles(lean, twist, 0)
	target.Neck = angles(headPitch, -twist * 0.5, 0)
	target.LeftShoulder = angles(leftArm, 0, leftRoll)
	target.RightShoulder = angles(rightArm, 0, rightRoll)
	target.LeftHip = angles(leftLeg, 0, -legRoll)
	target.RightHip = angles(rightLeg, 0, legRoll)
	return target, sinceHit < 0.55
end

local function updateRig(rig, now, dt)
	local model = rig.Model
	if not model.Parent or not rig.Root.Parent then
		remove(model)
		return
	end
	local state = model:GetAttribute("BossState") or "Sleep"
	local distance = cameraDistance(rig.Root.Position)
	if distance > ANIMATE_DISTANCE then
		rig.LastPosition = rig.Root.Position
		return
	end

	local target, fast = pose(rig, state, now, dt)
	if next(rig.Joints) then
		local alpha = 1 - math.exp(-dt * (fast and 30 or 14))
		for name, joint in pairs(rig.Joints) do
			local current = rig.Current[name]:Lerp(target[name], alpha)
			rig.Current[name] = current
			joint.Transform = current
		end
	end

	-- Пыль из-под ног на бегу, песчаный вихрь фараона
	local running = state == "Chase" and rig.RunBlend > 0.5
	if rig.RunDust then
		rig.RunDust.Rate = running and 25 or 0
	end
	if rig.SandSwirl then
		rig.SandSwirl.Rate = running and 12 or 0
	end

	-- «Z» над спящим
	if state == "Sleep" and distance < FX_DISTANCE and now - rig.LastZ > 1.3 then
		rig.LastZ = now
		sleepZ(rig)
	end
end

local bossFolder = workspace:WaitForChild("Bosses")
for _, model in ipairs(bossFolder:GetChildren()) do
	setup(model)
end
bossFolder.ChildAdded:Connect(function(model)
	-- Модель может прийти по частям (стриминг): даём ей долететь
	task.defer(setup, model)
	task.delay(1, setup, model)
end)
bossFolder.ChildRemoved:Connect(remove)

RunService.Stepped:Connect(function(_, dt)
	local now = os.clock()
	for _, rig in pairs(rigs) do
		local ok, err = pcall(updateRig, rig, now, dt)
		if not ok then
			warn("[BossFx] " .. tostring(err))
			remove(rig.Model)
		end
	end
end)

RunService.Heartbeat:Connect(updateDebris)

---------------------------------------------------------------------
-- Разовые события от сервера
---------------------------------------------------------------------

local function targetRoot(target)
	local character = typeof(target) == "Instance" and target:IsA("Player") and target.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

Remotes.Event("BossFx").OnClientEvent:Connect(function(model, kind, target)
	if typeof(model) ~= "Instance" then
		return
	end
	setup(model)
	local rig = rigs[model]
	if not rig then
		return
	end
	local now = os.clock()
	local style = rig.Style
	local scale = rig.Px / 0.35
	local position = rig.Root.Position
	local near = cameraDistance(position) < FX_DISTANCE

	if kind == "Wake" then
		rig.WakeStart = now
		if near then
			local feet = position - Vector3.new(0, rig.Root.Size.Y / 2 + rig.HipHeight, 0)
			ring(feet, style.Ring, 22 * scale, 0.7)
			burst(feet, style.Dust, 14, 16 * scale, 0.6 * scale)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - position).Magnitude < 80 then
				shake(0.6, 0.35)
			end
		end
	elseif kind == "Hit" then
		rig.HitStart = now
		local hitRoot = targetRoot(target)
		local at = hitRoot and hitRoot.Position or position
		if near or cameraDistance(at) < FX_DISTANCE then
			task.delay(0.22, function()
				ring(at, style.Ring, 16 * scale, 0.5)
				flash(at, style.Ring, 7 * scale)
				burst(at, style.Dust, 18, 22, 0.6)
				burst(at, { rgb(255, 255, 255) }, 6, 26, 0.35)
			end)
		end
		if target == player then
			shake(1.6, 0.55)
		end
	end
end)
