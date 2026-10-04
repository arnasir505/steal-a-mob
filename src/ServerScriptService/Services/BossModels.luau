-- BossModels: блочные модели боссов, собранные кодом.
--
-- Берутся, когда у биома нет своей модели босса (ни в модели биома, ни в
-- ReplicatedStorage.Assets.Bosses). Свою модель автора игра всегда ставит первой.
--
-- Каждая модель — риг из блоков с суставами Motor6D:
--   HumanoidRootPart -> Torso (RootJoint) -> Head (Neck), LeftArm/RightArm (Shoulder),
--   LeftLeg/RightLeg (Hip). Одежда, оружие, глаза приварены к своей части тела.
-- Анимации и эффекты (бег, сон, рык, удар, частицы) делает клиент: BossFx.client.luau.
-- Он узнаёт модель по атрибуту BossRig (имя модели) и двигает суставы сам —
-- загружать анимации в Roblox не нужно.
--
-- Размеры — в «пикселях» блочного персонажа (голова 8x8x8, тело 8x12x4, руки и
-- ноги 4x12x4), Px — сколько студов в одном пикселе. Модель смотрит в сторону -Z.

local BossModels = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local NEON = Enum.Material.Neon

---------------------------------------------------------------------
-- Сборка рига
---------------------------------------------------------------------

local function newPart(name, size, cframe, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = parent
	return part
end

local function motor(name, part0, part1, pivot)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * CFrame.new(pivot)
	m.C1 = part1.CFrame:Inverse() * CFrame.new(pivot)
	m.Parent = part0
	return m
end

-- spec: Px, Head/Torso/Arm/Leg = { x, y, z } в пикселях, цвета Skin/Shirt/Sleeve/Pants,
-- HeadOffset = { x, y, z } (сдвиг головы), Build = function(b) — детали
local function buildRig(name, spec)
	local px = spec.Px
	local H, T, A, L = spec.Head, spec.Torso, spec.Arm, spec.Leg
	local model = Instance.new("Model")
	model.Name = name

	local function v(x, y, z)
		return Vector3.new(x, y, z) * px
	end

	local legY = L[2]
	local headOffset = spec.HeadOffset or { 0, 0, 0 }
	local torsoCenter = v(0, legY + T[2] / 2, 0)

	local root = newPart("HumanoidRootPart", v(T[1], T[2], T[3]), CFrame.new(torsoCenter), rgb(255, 255, 255), nil, model)
	root.Transparency = 1

	local limbs = {}
	limbs.Torso = newPart("Torso", v(T[1], T[2], T[3]), CFrame.new(torsoCenter), spec.Shirt, spec.ShirtMaterial, model)
	limbs.Head = newPart("Head", v(H[1], H[2], H[3]),
		CFrame.new(v(headOffset[1], legY + T[2] + H[2] / 2 + headOffset[2], headOffset[3])), spec.Skin, spec.SkinMaterial, model)
	local armX = T[1] / 2 + A[1] / 2
	local armY = legY + T[2] - A[2] / 2
	limbs.LeftArm = newPart("LeftArm", v(A[1], A[2], A[3]), CFrame.new(v(-armX, armY, 0)), spec.Sleeve or spec.Shirt, spec.ShirtMaterial, model)
	limbs.RightArm = newPart("RightArm", v(A[1], A[2], A[3]), CFrame.new(v(armX, armY, 0)), spec.Sleeve or spec.Shirt, spec.ShirtMaterial, model)
	local legX = math.max(L[1] / 2, T[1] / 4)
	limbs.LeftLeg = newPart("LeftLeg", v(L[1], L[2], L[3]), CFrame.new(v(-legX, legY / 2, 0)), spec.Pants, spec.PantsMaterial, model)
	limbs.RightLeg = newPart("RightLeg", v(L[1], L[2], L[3]), CFrame.new(v(legX, legY / 2, 0)), spec.Pants, spec.PantsMaterial, model)

	motor("RootJoint", root, limbs.Torso, v(0, legY, 0))
	motor("Neck", limbs.Torso, limbs.Head, v(headOffset[1], legY + T[2] + headOffset[2], headOffset[3]))
	local shoulderY = legY + T[2] - A[1] / 2
	motor("LeftShoulder", limbs.Torso, limbs.LeftArm, v(-armX, shoulderY, 0))
	motor("RightShoulder", limbs.Torso, limbs.RightArm, v(armX, shoulderY, 0))
	motor("LeftHip", limbs.Torso, limbs.LeftLeg, v(-legX, legY, 0))
	motor("RightHip", limbs.Torso, limbs.RightLeg, v(legX, legY, 0))

	-- b.Add(часть тела, имя, размер, сдвиг от центра части, цвет, материал, поворот)
	-- Размер и сдвиг — в пикселях. Деталь приваривается к части тела.
	local b = {}
	b.Limbs = limbs
	b.Px = px
	function b.Add(limbName, partName, size, offset, color, material, rotation)
		local limb = limbs[limbName]
		local cframe = limb.CFrame * CFrame.new(Vector3.new(offset[1], offset[2], offset[3]) * px)
		if rotation then
			cframe *= rotation
		end
		local part = newPart(partName, Vector3.new(size[1], size[2], size[3]) * px, cframe, color, material, model)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = limb
		weld.Part1 = part
		weld.Parent = part
		return part
	end
	-- Плоская деталь на лицевой стороне (-Z) части тела: x, y — центр от середины грани
	function b.Face(limbName, partName, x, y, w, h, color, material, depth)
		local limb = limbs[limbName]
		local d = depth or 0.3
		local z = -(limb.Size.Z / px) / 2 - d / 2
		return b.Add(limbName, partName, { w, h, d }, { x, y, z }, color, material)
	end
	-- Деталь на спине (+Z)
	function b.Back(limbName, partName, x, y, w, h, color, material, depth)
		local limb = limbs[limbName]
		local d = depth or 0.3
		local z = (limb.Size.Z / px) / 2 + d / 2
		return b.Add(limbName, partName, { w, h, d }, { x, y, z }, color, material)
	end
	-- Свет и огонь
	function b.Light(part, color, range, brightness)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness or 1
		light.Parent = part
		return light
	end

	if spec.Build then
		spec.Build(b, spec)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- у R15 HipHeight считается от низа корня
	humanoid.HipHeight = legY * px
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	model.PrimaryPart = root
	-- При стриминге модель приходит игроку целиком, а не по кусочкам
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	-- Клиент (BossFx) по этим атрибутам понимает, что модель можно анимировать кодом
	model:SetAttribute("BossRig", name)
	model:SetAttribute("RigPx", px)
	model:SetAttribute("LegLength", legY * px)
	return model
end

---------------------------------------------------------------------
-- Боссы
---------------------------------------------------------------------

local SPECS = {}

-- Фермер (Plains): соломенная шляпа, клетчатая рубаха, комбинезон, вилы
SPECS.Farmer = {
	Px = 0.34,
	Head = { 8, 8, 8 }, Torso = { 8, 12, 4 }, Arm = { 4, 12, 4 }, Leg = { 4, 12, 4 },
	Skin = rgb(224, 172, 128), Shirt = rgb(178, 48, 40), Pants = rgb(58, 88, 150),
	Build = function(b)
		local skin, denim, straw = rgb(224, 172, 128), rgb(58, 88, 150), rgb(226, 196, 104)
		local dark, white, brown = rgb(30, 24, 20), rgb(245, 245, 245), rgb(110, 70, 40)
		-- Лицо
		for _, s in ipairs({ -1, 1 }) do
			b.Face("Head", "EyeWhite", s * 2, 0.5, 2, 1, white)
			b.Face("Head", "Pupil", s * 1.5, 0.5, 1, 1, dark, nil, 0.4)
		end
		b.Add("Head", "Nose", { 2, 2, 1.5 }, { 0, -1, -4.75 }, rgb(205, 150, 110))
		b.Face("Head", "Mustache", 0, -2.5, 6, 1, rgb(120, 76, 40))
		b.Face("Head", "Cheeks", 0, -3.5, 8, 1, rgb(210, 160, 118), nil, 0.2)
		-- Соломенная шляпа с красной лентой
		b.Add("Head", "HatBrim", { 13, 1, 13 }, { 0, 4.5, 0 }, straw)
		b.Add("Head", "HatCrown", { 8.4, 3, 8.4 }, { 0, 6.5, 0 }, straw)
		b.Add("Head", "HatBand", { 8.6, 1, 8.6 }, { 0, 5.5, 0 }, rgb(170, 40, 35))
		-- Комбинезон поверх рубахи
		b.Add("Torso", "Overalls", { 8.2, 6, 4.2 }, { 0, -3, 0 }, denim)
		b.Face("Torso", "Bib", 0, 1.5, 5, 4, denim, nil, 0.4)
		b.Face("Torso", "Pocket", 0, 1, 2.5, 1.5, rgb(46, 72, 128), nil, 0.6)
		for _, s in ipairs({ -1, 1 }) do
			b.Face("Torso", "Strap", s * 2.5, 4.5, 1, 3, denim, nil, 0.4)
			b.Face("Torso", "Button", s * 2.5, 3.2, 0.8, 0.8, rgb(230, 200, 80), nil, 0.6)
			b.Back("Torso", "StrapBack", s * 2.5, 2.5, 1, 7, denim, nil, 0.4)
		end
		-- Клетка на рубахе (рукава)
		for _, arm in ipairs({ "LeftArm", "RightArm" }) do
			b.Add(arm, "Plaid", { 4.2, 1, 4.2 }, { 0, 3, 0 }, rgb(120, 28, 24))
			b.Add(arm, "Plaid", { 4.2, 1, 4.2 }, { 0, 0, 0 }, rgb(120, 28, 24))
			b.Add(arm, "Hand", { 4.2, 3, 4.2 }, { 0, -4.5, 0 }, skin)
		end
		for _, leg in ipairs({ "LeftLeg", "RightLeg" }) do
			b.Add(leg, "Boot", { 4.3, 3, 4.6 }, { 0, -4.5, -0.2 }, brown)
		end
		-- Вилы в правой руке (смотрят вперёд)
		local wood, metal = rgb(150, 105, 60), rgb(160, 165, 175)
		b.Add("RightArm", "Shaft", { 1, 1, 22 }, { 0, -5, -7 }, wood)
		b.Add("RightArm", "ForkBar", { 6, 1, 1 }, { 0, -5, -18 }, metal, Enum.Material.Metal)
		for _, x in ipairs({ -2.5, 0, 2.5 }) do
			b.Add("RightArm", "Tine", { 0.8, 0.8, 5 }, { x, -5, -20.5 }, metal, Enum.Material.Metal)
		end
	end,
}

-- Лесоруб (Forest): шапка, рыжая борода, клетчатая рубаха, большой топор
SPECS.Lumberjack = {
	Px = 0.36,
	Head = { 8, 8, 8 }, Torso = { 10, 12, 5 }, Arm = { 5, 12, 5 }, Leg = { 5, 12, 5 },
	Skin = rgb(214, 160, 120), Shirt = rgb(176, 32, 30), Pants = rgb(48, 66, 104),
	Build = function(b)
		local black, beard, white = rgb(28, 22, 22), rgb(156, 82, 36), rgb(240, 240, 240)
		-- Клетка: тёмные полосы на рубахе и рукавах
		for _, y in ipairs({ 3, -1, -5 }) do
			b.Add("Torso", "Plaid", { 10.2, 1.4, 5.2 }, { 0, y, 0 }, black)
		end
		for _, x in ipairs({ -2.5, 2.5 }) do
			b.Add("Torso", "Plaid", { 1.4, 12.2, 5.2 }, { x, 0, 0 }, black)
		end
		for _, arm in ipairs({ "LeftArm", "RightArm" }) do
			b.Add(arm, "Plaid", { 5.2, 1.4, 5.2 }, { 0, 3, 0 }, black)
			b.Add(arm, "Plaid", { 5.2, 1.4, 5.2 }, { 0, -1, 0 }, black)
			b.Add(arm, "Hand", { 5.2, 3, 5.2 }, { 0, -4.5, 0 }, rgb(214, 160, 120))
		end
		b.Add("Torso", "Belt", { 10.3, 1.5, 5.3 }, { 0, -5.3, 0 }, rgb(70, 45, 25))
		b.Face("Torso", "Buckle", 0, -5.3, 2, 1.5, rgb(200, 170, 80), Enum.Material.Metal, 0.5)
		-- Лицо и борода
		for _, s in ipairs({ -1, 1 }) do
			b.Face("Head", "EyeWhite", s * 2, 0.5, 2, 1, white)
			b.Face("Head", "Pupil", s * 1.5, 0.5, 1, 1, black, nil, 0.4)
			b.Face("Head", "Brow", s * 2, 1.7, 2.5, 0.8, beard, nil, 0.4)
			b.Add("Head", "Sideburn", { 1, 5, 8.2 }, { s * 3.6, -1.5, 0 }, beard)
		end
		b.Face("Head", "Beard", 0, -2.5, 8.2, 3, beard, nil, 1)
		b.Add("Head", "BeardTip", { 5, 3, 2 }, { 0, -5, -3.2 }, beard)
		b.Face("Head", "Nose", 0, -0.7, 1.6, 1.6, rgb(196, 140, 100), nil, 1)
		-- Шапка с помпоном
		b.Add("Head", "Beanie", { 8.6, 3.2, 8.6 }, { 0, 3, 0 }, rgb(50, 96, 60))
		b.Add("Head", "BeanieRim", { 8.8, 1.2, 8.8 }, { 0, 1.6, 0 }, rgb(36, 72, 44))
		b.Add("Head", "Pompom", { 2.4, 2.4, 2.4 }, { 0, 5.6, 0 }, white)
		for _, leg in ipairs({ "LeftLeg", "RightLeg" }) do
			b.Add(leg, "Boot", { 5.3, 3.5, 5.6 }, { 0, -4.3, -0.2 }, rgb(60, 40, 26))
		end
		-- Топор в правой руке
		local wood, metal = rgb(122, 82, 46), rgb(150, 155, 165)
		b.Add("RightArm", "AxeHandle", { 1.2, 1.2, 18 }, { 0, -5, -6 }, wood)
		b.Add("RightArm", "AxeHead", { 1, 6, 5 }, { 0, -3, -14 }, metal, Enum.Material.Metal)
		b.Add("RightArm", "AxeEdge", { 1.1, 7, 1 }, { 0, -3, -16.8 }, rgb(215, 220, 230), Enum.Material.Metal)
	end,
}

-- Фараон (Desert): полосатый платок, бинты, золотой воротник, жезл-крюк, светящиеся глаза
SPECS.Pharaoh = {
	Px = 0.35,
	Head = { 8, 8, 8 }, Torso = { 8, 12, 4 }, Arm = { 4, 12, 4 }, Leg = { 4, 12, 4 },
	Skin = rgb(70, 54, 42), Shirt = rgb(214, 200, 164), Pants = rgb(214, 200, 164),
	Build = function(b)
		local gold, blue, wrap = rgb(232, 184, 52), rgb(36, 66, 160), rgb(180, 166, 130)
		-- Бинты: тёмные полосы по телу
		for _, y in ipairs({ 4, 0, -4 }) do
			b.Add("Torso", "Wrap", { 8.2, 1, 4.2 }, { 0, y, 0 }, wrap)
		end
		for _, limb in ipairs({ "LeftArm", "RightArm", "LeftLeg", "RightLeg" }) do
			for _, y in ipairs({ 3.5, -0.5, -4.5 }) do
				b.Add(limb, "Wrap", { 4.2, 1, 4.2 }, { 0, y, 0 }, wrap)
			end
		end
		-- Платок-немес в полоску: макушка и два крыла до плеч
		b.Add("Head", "NemesTop", { 8.8, 3, 8.8 }, { 0, 3, 0.2 }, gold)
		b.Add("Head", "NemesStripe", { 9, 1, 9 }, { 0, 2.2, 0.2 }, blue)
		b.Add("Head", "NemesBack", { 8.8, 9, 2 }, { 0, -1.5, 4.2 }, gold)
		for _, s in ipairs({ -1, 1 }) do
			for k = 0, 3 do
				b.Add("Head", "NemesFlap", { 2, 2, 3 }, { s * 4.8, 1 - k * 2, -0.5 }, k % 2 == 0 and gold or blue)
			end
			b.Face("Head", "Eye", s * 2, 0.5, 2, 1, rgb(80, 240, 255), NEON, 0.4)
		end
		b.Add("Head", "Cobra", { 1.2, 2.5, 1 }, { 0, 4, -4.6 }, gold, Enum.Material.Metal)
		b.Face("Head", "Beard", 0, -4.5, 1.6, 4, gold, Enum.Material.Metal, 1)
		-- Широкий воротник и пояс с юбкой
		b.Add("Torso", "Collar", { 9.4, 2, 5 }, { 0, 5, 0 }, gold, Enum.Material.Metal)
		b.Add("Torso", "CollarStripe", { 9.6, 1, 5.2 }, { 0, 3.5, 0 }, blue)
		b.Face("Torso", "Gem", 0, 4.5, 1.5, 1.5, rgb(60, 200, 220), NEON, 0.6)
		b.Add("Torso", "Belt", { 8.4, 1.5, 4.4 }, { 0, -5, 0 }, gold, Enum.Material.Metal)
		b.Add("Torso", "Kilt", { 9, 4, 5 }, { 0, -7.5, 0 }, rgb(240, 236, 220))
		for _, arm in ipairs({ "LeftArm", "RightArm" }) do
			b.Add(arm, "Bracer", { 4.4, 2, 4.4 }, { 0, -2.5, 0 }, gold, Enum.Material.Metal)
		end
		-- Жезл-крюк в правой руке
		b.Add("RightArm", "Crook", { 1, 1, 18 }, { 0, -5, -6 }, gold, Enum.Material.Metal)
		for k = 0, 3 do
			b.Add("RightArm", "CrookBand", { 1.2, 1.2, 1 }, { 0, -5, -1 - k * 4 }, blue)
		end
		b.Add("RightArm", "Hook", { 1, 4, 1 }, { 0, -3, -15.5 }, gold, Enum.Material.Metal)
		b.Add("RightArm", "HookTip", { 1, 1, 3 }, { 0, -1.5, -14 }, gold, Enum.Material.Metal)
		local eyeGlow = b.Add("Head", "EyeGlow", { 1, 1, 1 }, { 0, 0.5, -3.5 }, rgb(80, 240, 255))
		eyeGlow.Transparency = 1
		b.Light(eyeGlow, rgb(80, 240, 255), 10, 1)
	end,
}

-- Йети (Snow): огромный, белый мех, длинные руки, рожки, клыки
SPECS.Yeti = {
	Px = 0.42,
	Head = { 9, 9, 8 }, Torso = { 14, 13, 8 }, Arm = { 6, 16, 6 }, Leg = { 6, 10, 6 },
	HeadOffset = { 0, -1, -1.5 },
	Skin = rgb(236, 242, 248), Shirt = rgb(236, 242, 248), Pants = rgb(226, 234, 242),
	Build = function(b)
		local face, dark, fur2 = rgb(108, 140, 172), rgb(24, 30, 44), rgb(205, 218, 232)
		local horn, white = rgb(160, 170, 185), rgb(250, 250, 250)
		-- Морда: голубая маска, глаза, рот с клыками
		b.Face("Head", "Face", 0, -0.5, 7, 6, face, nil, 0.4)
		for _, s in ipairs({ -1, 1 }) do
			b.Face("Head", "Eye", s * 1.8, 1, 1.6, 1.4, dark, nil, 0.7)
			b.Face("Head", "Glint", s * 1.5, 1.3, 0.6, 0.6, white, nil, 0.8)
			b.Face("Head", "Fang", s * 1.6, -2.2, 0.8, 1.4, white, nil, 0.8)
			b.Add("Head", "Horn", { 1.5, 3, 1.5 }, { s * 4, 5, 0.5 }, horn)
			b.Add("Head", "HornTip", { 1.2, 1.2, 2.5 }, { s * 4.4, 6.5, 1.5 }, horn)
			b.Add("Head", "Ear", { 1, 2, 2 }, { s * 5, 1, 1 }, fur2)
		end
		b.Face("Head", "Mouth", 0, -2.8, 4.5, 1.2, dark, nil, 0.6)
		b.Face("Head", "Nose", 0, -0.5, 2, 1.2, dark, nil, 0.8)
		b.Add("Head", "Tuft", { 6, 2, 6 }, { 0, 5, 0 }, white)
		-- Мех: клочья на груди, плечах и спине
		b.Face("Torso", "ChestFur", 0, 1, 10, 8, fur2, nil, 0.6)
		b.Add("Torso", "Hump", { 12, 5, 3 }, { 0, 4, 5 }, white)
		for _, s in ipairs({ -1, 1 }) do
			b.Add("Torso", "ShoulderFur", { 5, 3, 8.6 }, { s * 5.5, 6, 0 }, white)
		end
		for _, arm in ipairs({ "LeftArm", "RightArm" }) do
			b.Add(arm, "ArmFur", { 6.6, 4, 6.6 }, { 0, 3, 0 }, white)
			b.Add(arm, "Hand", { 6.6, 4, 6.6 }, { 0, -7, 0 }, face)
			for _, x in ipairs({ -2, 0, 2 }) do
				b.Add(arm, "Claw", { 1, 1.5, 1 }, { x, -9.6, -2.5 }, white)
			end
		end
		for _, leg in ipairs({ "LeftLeg", "RightLeg" }) do
			b.Add(leg, "Foot", { 6.8, 2, 8 }, { 0, -4, -1 }, face)
			b.Add(leg, "LegFur", { 6.6, 3, 6.6 }, { 0, 2.5, 0 }, white)
		end
	end,
}

-- Болотный отшельник (Swamp): горбатый, капюшон со мхом, длинный нос, посох с фонарём
SPECS.BogHermit = {
	Px = 0.35,
	Head = { 8, 8, 8 }, Torso = { 8, 12, 5 }, Arm = { 3.5, 12, 3.5 }, Leg = { 4, 12, 4 },
	HeadOffset = { 0, -1, -1.5 },
	Skin = rgb(146, 168, 106), Shirt = rgb(56, 76, 46), Pants = rgb(48, 64, 40),
	Build = function(b)
		local robe, moss, dark = rgb(56, 76, 46), rgb(92, 130, 52), rgb(26, 32, 22)
		local glow = rgb(140, 255, 90)
		-- Лицо: жёлтые глаза, длинный нос с бородавкой, жидкая борода
		for _, s in ipairs({ -1, 1 }) do
			b.Face("Head", "Eye", s * 2, 0.5, 1.5, 1, rgb(250, 230, 60), NEON, 0.4)
		end
		b.Add("Head", "Nose", { 2, 2, 4 }, { 0, -1, -6 }, rgb(130, 152, 92))
		b.Add("Head", "Wart", { 0.8, 0.8, 0.8 }, { 0.8, -0.2, -7 }, rgb(96, 118, 64))
		b.Face("Head", "Beard", 0, -3.2, 5, 2, rgb(170, 175, 150), nil, 0.6)
		b.Add("Head", "BeardTip", { 3, 3, 1 }, { 0, -5.5, -4.2 }, rgb(170, 175, 150))
		-- Капюшон с острым кончиком назад и мхом
		b.Add("Head", "HoodTop", { 9.4, 2, 9.4 }, { 0, 4.8, 0.3 }, robe)
		b.Add("Head", "HoodBack", { 9.4, 9, 2 }, { 0, 0, 4.6 }, robe)
		for _, s in ipairs({ -1, 1 }) do
			b.Add("Head", "HoodSide", { 1, 9, 9 }, { s * 4.7, 0, 0.5 }, robe)
		end
		b.Add("Head", "HoodTip", { 5, 3, 5 }, { 0, 7, 2 }, robe)
		b.Add("Head", "HoodTip2", { 3, 2.5, 3 }, { 0, 9, 3.5 }, robe)
		b.Add("Head", "HoodTip3", { 2, 2, 2 }, { 0, 10, 5.5 }, robe)
		b.Add("Head", "Moss", { 4, 1, 3 }, { -2, 5.9, 0 }, moss)
		b.Add("Head", "Moss", { 3, 1, 2 }, { 2.5, 5.9, 2 }, moss)
		-- Балахон: длинный подол, верёвка-пояс, заплатки, мох на плечах
		b.Add("Torso", "Robe", { 9, 8, 6 }, { 0, -9, 0 }, robe)
		b.Add("Torso", "Rope", { 8.4, 1, 5.4 }, { 0, -3.5, 0 }, rgb(150, 120, 70))
		b.Face("Torso", "Patch", -2, 1, 2.5, 2.5, rgb(90, 70, 46), nil, 0.4)
		b.Face("Torso", "Patch", 2.5, -6.5, 2, 2, rgb(70, 60, 90), nil, 0.4)
		for _, s in ipairs({ -1, 1 }) do
			b.Add("Torso", "ShoulderMoss", { 4, 1.5, 5.4 }, { s * 4.5, 6.4, 0 }, moss)
		end
		for _, arm in ipairs({ "LeftArm", "RightArm" }) do
			b.Add(arm, "Sleeve", { 4.4, 4, 4.4 }, { 0, -3.5, 0 }, robe)
			b.Add(arm, "Hand", { 3.6, 2.5, 3.6 }, { 0, -6.5, 0 }, rgb(146, 168, 106))
		end
		for _, leg in ipairs({ "LeftLeg", "RightLeg" }) do
			b.Add(leg, "Foot", { 4.2, 2, 5 }, { 0, -5, -0.5 }, dark)
		end
		-- Кривой посох с банкой-фонарём на конце
		local wood = rgb(84, 64, 40)
		b.Add("RightArm", "Staff", { 1.2, 1.2, 12 }, { 0, -6, -4 }, wood)
		b.Add("RightArm", "Staff2", { 1.2, 1.2, 8 }, { 0, -5, -13 }, wood, nil, CFrame.Angles(math.rad(-15), 0, 0))
		b.Add("RightArm", "JarLid", { 3, 1, 3 }, { 0, -2, -17 }, wood)
		local jar = b.Add("RightArm", "Jar", { 2.6, 3, 2.6 }, { 0, -4, -17 }, glow, NEON)
		jar.Transparency = 0.15
		b.Light(jar, glow, 16, 1.5)
	end,
}

-- Король пламени (Underworld): обсидиановые латы с лавой, корона в огне, плащ, булава
SPECS.InfernoKing = {
	Px = 0.4,
	Head = { 8, 8, 8 }, Torso = { 10, 12, 6 }, Arm = { 5, 13, 5 }, Leg = { 5, 12, 5 },
	Skin = rgb(38, 28, 44), Shirt = rgb(38, 28, 44), Pants = rgb(32, 24, 38),
	SkinMaterial = Enum.Material.Slate, ShirtMaterial = Enum.Material.Slate, PantsMaterial = Enum.Material.Slate,
	Build = function(b)
		local lava, gold, cape = rgb(255, 110, 20), rgb(236, 180, 40), rgb(150, 20, 24)
		local metal = Enum.Material.Metal
		-- Шлем: щель с горящими глазами
		b.Face("Head", "Visor", 0, 0.5, 7, 1.2, rgb(255, 210, 60), NEON, 0.4)
		b.Face("Head", "Jaw", 0, -2.5, 6, 2, rgb(28, 20, 32), Enum.Material.Slate, 0.6)
		b.Face("Head", "Crack", -2, -2.5, 1, 2, lava, NEON, 0.7)
		-- Корона с зубцами и рубинами
		b.Add("Head", "Crown", { 9, 2, 9 }, { 0, 4.8, 0 }, gold, metal)
		for _, p in ipairs({ { -3.5, -3.5 }, { 3.5, -3.5 }, { -3.5, 3.5 }, { 3.5, 3.5 }, { 0, -4.2 }, { 0, 4.2 }, { -4.2, 0 }, { 4.2, 0 } }) do
			b.Add("Head", "Spike", { 1.4, 3, 1.4 }, { p[1], 7, p[2] }, gold, metal)
		end
		b.Face("Head", "Ruby", 0, 4.8, 1.6, 1.4, rgb(255, 40, 40), NEON, 0.9)
		local flame = b.Add("Head", "FlameAnchor", { 1, 1, 1 }, { 0, 6, 0 }, lava)
		flame.Transparency = 1
		local fire = Instance.new("Fire")
		fire.Size = 6
		fire.Heat = 12
		fire.Color = rgb(255, 120, 30)
		fire.SecondaryColor = rgb(255, 220, 80)
		fire.Parent = flame
		b.Light(flame, rgb(255, 130, 40), 22, 1.5)
		-- Латы: трещины лавы, наплечники, плащ
		b.Face("Torso", "LavaV", 0, 0, 1, 10, lava, NEON, 0.4)
		b.Face("Torso", "LavaH", 0, 2, 7, 1, lava, NEON, 0.4)
		b.Face("Torso", "Core", 0, 2, 2.5, 2.5, rgb(255, 200, 60), NEON, 0.7)
		b.Add("Torso", "Belt", { 10.4, 1.5, 6.4 }, { 0, -5.3, 0 }, gold, metal)
		b.Back("Torso", "Cape", 0, -4, 10, 18, cape, Enum.Material.Fabric, 0.8)
		for _, s in ipairs({ -1, 1 }) do
			local arm = s < 0 and "LeftArm" or "RightArm"
			b.Add(arm, "Pauldron", { 6.6, 3, 6.6 }, { 0, 5.5, 0 }, rgb(48, 36, 54), Enum.Material.Slate)
			b.Add(arm, "PauldronTrim", { 6.8, 1, 6.8 }, { 0, 4, 0 }, gold, metal)
			b.Add(arm, "PauldronSpike", { 1.5, 3, 1.5 }, { 0, 8, 0 }, gold, metal)
			b.Face(arm, "Crack", 0, -1, 1, 6, lava, NEON, 0.4)
			b.Add(arm, "Gauntlet", { 5.6, 3, 5.6 }, { 0, -5, 0 }, rgb(28, 20, 32), Enum.Material.Slate)
		end
		for _, leg in ipairs({ "LeftLeg", "RightLeg" }) do
			b.Face(leg, "Crack", 0, 1, 1, 6, lava, NEON, 0.4)
			b.Add(leg, "Boot", { 5.6, 3, 6.2 }, { 0, -4.5, -0.3 }, rgb(28, 20, 32), Enum.Material.Slate)
		end
		-- Булава с шипами
		b.Add("RightArm", "MaceShaft", { 1.2, 1.2, 14 }, { 0, -6, -5 }, gold, metal)
		b.Add("RightArm", "MaceHead", { 4.5, 4.5, 4.5 }, { 0, -6, -13 }, rgb(30, 22, 34), Enum.Material.Slate)
		for _, d in ipairs({ { 0, 3, 0 }, { 0, -3, 0 }, { 3, 0, 0 }, { -3, 0, 0 }, { 0, 0, -3 } }) do
			b.Add("RightArm", "MaceSpike", { 1.2, 1.2, 1.2 }, { d[1], -6 + d[2], -13 + d[3] }, lava, NEON)
		end
	end,
}

-- Страж кристаллов (CrystalCave): каменный голем, кристаллы из плеч и спины, светящееся ядро
SPECS.GemWarden = {
	Px = 0.44,
	Head = { 7, 7, 7 }, Torso = { 16, 14, 9 }, Arm = { 6, 18, 6 }, Leg = { 6, 10, 6 },
	HeadOffset = { 0, -2, -2 },
	Skin = rgb(106, 100, 118), Shirt = rgb(96, 90, 108), Pants = rgb(84, 80, 96),
	SkinMaterial = Enum.Material.Slate, ShirtMaterial = Enum.Material.Slate, PantsMaterial = Enum.Material.Slate,
	Build = function(b)
		local cyan, purple, pink = rgb(90, 230, 255), rgb(170, 100, 255), rgb(255, 110, 200)
		local stone2, moss = rgb(76, 72, 88), rgb(70, 110, 80)
		local slate = Enum.Material.Slate
		-- Голова: брови-плиты, глаза-щели
		b.Face("Head", "Brow", 0, 1.8, 7.2, 1.5, stone2, slate, 1)
		for _, s in ipairs({ -1, 1 }) do
			b.Face("Head", "Eye", s * 1.8, 0.4, 1.8, 0.9, purple, NEON, 0.4)
		end
		b.Face("Head", "Mouth", 0, -2, 4, 1, rgb(40, 36, 50), slate, 0.4)
		b.Add("Head", "CrownCrystal", { 1.5, 4, 1.5 }, { 0, 5, 0 }, cyan, NEON, CFrame.Angles(0, 0, math.rad(12)))
		-- Ядро в груди, плиты и мох
		local core = b.Face("Torso", "Core", 0, 1.5, 4, 4, cyan, NEON, 0.6)
		b.Light(core, cyan, 20, 1.5)
		b.Face("Torso", "CoreRim", 0, 1.5, 6, 6, stone2, slate, 0.3)
		b.Face("Torso", "Plate", -4.5, -4, 5, 4, stone2, slate, 0.5)
		b.Face("Torso", "Plate", 4.5, -4.5, 4, 3, stone2, slate, 0.5)
		b.Add("Torso", "Moss", { 6, 1, 4 }, { -4, 7.4, 1 }, moss)
		b.Add("Torso", "Moss", { 3, 1, 5 }, { 5, 7.4, -1 }, moss)
		-- Кристаллы на спине и плечах (наклонённые)
		local backCrystals = {
			{ -4, 5, 5, purple, 6, -20 }, { 0, 6, 5.5, cyan, 8, 0 }, { 4, 4, 5, pink, 6, 20 },
			{ -2, 0, 5, cyan, 5, -10 }, { 3, -1, 5, purple, 4, 15 },
		}
		for _, c in ipairs(backCrystals) do
			b.Add("Torso", "Crystal", { 2, c[5], 2 }, { c[1], c[2], c[3] }, c[4], NEON,
				CFrame.Angles(math.rad(35), 0, math.rad(c[6])))
		end
		for _, s in ipairs({ -1, 1 }) do
			local arm = s < 0 and "LeftArm" or "RightArm"
			b.Add(arm, "ShoulderRock", { 7, 4, 7 }, { 0, 7, 0 }, stone2, slate)
			b.Add(arm, "ShoulderCrystal", { 1.8, 5, 1.8 }, { s * 1, 10.5, 0 }, s < 0 and pink or purple, NEON,
				CFrame.Angles(0, 0, math.rad(-s * 25)))
			b.Add(arm, "ShoulderCrystal2", { 1.2, 3, 1.2 }, { -s * 1.5, 9.5, 1.5 }, cyan, NEON,
				CFrame.Angles(math.rad(20), 0, math.rad(s * 15)))
			-- Огромные кулаки
			b.Add(arm, "Fist", { 7.5, 5, 7.5 }, { 0, -8, 0 }, stone2, slate)
			b.Add(arm, "FistCrystal", { 1.5, 2.5, 1.5 }, { 0, -8, -4.2 }, cyan, NEON, CFrame.Angles(math.rad(-70), 0, 0))
			b.Face(arm, "Vein", 0, 0, 1, 8, s < 0 and purple or cyan, NEON, 0.3)
		end
		for _, leg in ipairs({ "LeftLeg", "RightLeg" }) do
			b.Add(leg, "Foot", { 7, 3, 8 }, { 0, -3.5, -1 }, stone2, slate)
		end
	end,
}

-- Есть ли встроенная модель для этого имени
function BossModels.Has(name)
	return SPECS[name] ~= nil
end

-- Новая модель босса или nil, если такого нет
function BossModels.Build(name)
	local spec = SPECS[name]
	if not spec then
		return nil
	end
	return buildRig(name, spec)
end

return BossModels
