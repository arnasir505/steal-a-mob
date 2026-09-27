-- RagdollService: игрок падает "тряпичной куклой" и через немного встаёт.
-- Урона нет. Сейчас так падают от толчка босса, на этапе 6 можно и от меча.
--
--   RagdollService.Ragdoll(player, seconds)
--   RagdollService.IsRagdolled(player)
--
-- Как устроено:
--  * суставы рук, ног и пояса (Motor6D) выключаются, а на их место ставятся
--    шарниры (BallSocketConstraint) — конечности болтаются свободно;
--  * в части тела кладутся невидимые "кости" с столкновениями: у рук и ног
--    Roblox столкновения выключает, и без этого они проваливались бы в пол;
--  * Humanoid переводится в PlatformStand, чтобы не пытался стоять;
--  * через seconds всё возвращается как было, и игрок встаёт
--    (клиент помогает встать сразу — Ragdoll.client.luau).
-- Суставы корня и шеи не трогаем: корень держит тело вместе, чтобы толчок
-- уносил всего игрока, а без шеи Humanoid может погибнуть.
-- Всё делается на сервере, поэтому падение видят все игроки.

local PhysicsService = game:GetService("PhysicsService")

local RagdollService = {}

-- Группа столкновений: части упавшего игрока не толкаются друг с другом,
-- но лежат на земле
local GROUP = "Ragdoll"
local KEEP_JOINTS = { Root = true, RootJoint = true, Neck = true }

local active = {} -- [character] = { Until, Created, Motors, Groups }

local function makeSocket(motor, created)
	local a0 = Instance.new("Attachment")
	a0.Name = "RagdollAttachment"
	a0.CFrame = motor.C0
	a0.Parent = motor.Part0

	local a1 = Instance.new("Attachment")
	a1.Name = "RagdollAttachment"
	a1.CFrame = motor.C1
	a1.Parent = motor.Part1

	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "RagdollSocket"
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	-- Ограничения, чтобы руки и ноги не выворачивало как попало
	socket.LimitsEnabled = true
	socket.UpperAngle = 60
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -45
	socket.TwistUpperAngle = 45
	socket.Parent = motor.Part0

	table.insert(created, a0)
	table.insert(created, a1)
	table.insert(created, socket)
end

local function makeCollider(part, created)
	local collider = Instance.new("Part")
	collider.Name = "RagdollCollider"
	collider.Size = part.Size * 0.7
	collider.CFrame = part.CFrame
	collider.Transparency = 1
	collider.CanCollide = true
	collider.CanQuery = false
	collider.CanTouch = false
	collider.Massless = true
	collider.CollisionGroup = GROUP

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = collider
	weld.Parent = collider

	collider.Parent = part
	table.insert(created, collider)
end

-- Возвращает всё как было
local function finish(character, state)
	if active[character] ~= state then
		return
	end
	active[character] = nil

	for _, instance in ipairs(state.Created) do
		instance:Destroy()
	end
	for _, motor in ipairs(state.Motors) do
		if motor.Parent then
			motor.Enabled = true
		end
	end
	for part, group in pairs(state.Groups) do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
	character:SetAttribute("Ragdoll", false)
end

function RagdollService.IsRagdolled(player)
	local character = player.Character
	return character ~= nil and active[character] ~= nil
end

-- Уронить игрока на seconds секунд. Если он уже лежит — просто продлеваем.
function RagdollService.Ragdoll(player, seconds)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	-- На беговой дорожке персонаж заякорен — там падать некуда
	if not humanoid or not root or humanoid.Health <= 0 or root.Anchored then
		return false
	end

	local untilTime = os.clock() + seconds
	local state = active[character]
	if state then
		state.Until = math.max(state.Until, untilTime)
		return true
	end

	state = { Until = untilTime, Created = {}, Motors = {}, Groups = {} }
	active[character] = state

	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Enabled and not KEEP_JOINTS[motor.Name]
			and motor.Part0 and motor.Part1 then
			makeSocket(motor, state.Created)
			motor.Enabled = false
			table.insert(state.Motors, motor)
		end
	end

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			state.Groups[part] = part.CollisionGroup
			part.CollisionGroup = GROUP
			-- "Кости" только частям тела, шапкам и прочим аксессуарам не нужно
			if part.Parent == character then
				makeCollider(part, state.Created)
			end
		end
	end

	humanoid.PlatformStand = true
	character:SetAttribute("Ragdoll", true)

	task.spawn(function()
		while active[character] == state and character.Parent and os.clock() < state.Until do
			task.wait(0.05)
		end
		finish(character, state)
	end)
	return true
end

function RagdollService.Init()
	if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
		PhysicsService:RegisterCollisionGroup(GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end

return RagdollService
