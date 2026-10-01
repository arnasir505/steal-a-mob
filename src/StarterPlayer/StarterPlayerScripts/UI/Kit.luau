-- Kit: общие детали интерфейса — цвета, шрифт, текст с обводкой, кнопки, окна.
-- Все экраны собираются из этих деталей, поэтому выглядят одинаково.
--
-- Размеры везде в пикселях для экрана 1920x1080. На других экранах всё
-- уменьшается или увеличивается само (Kit.AutoScale).
--
-- Правила интерфейса (CLAUDE.md, баг с курсором):
--  * у декоративных Frame Active = false;
--  * Modal = true только у кнопки закрытия окна — пока окно открыто, курсор свободен.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIAssets = require(ReplicatedStorage.Shared.Config.UIAssets)

local Kit = {}

Kit.Font = Enum.Font.FredokaOne
Kit.Robux = utf8.char(0xE002) -- значок Robux: встроенный символ шрифтов Roblox

Kit.Colors = {
	Green = Color3.fromRGB(101, 255, 43),
	Blue = Color3.fromRGB(46, 195, 255),
	Purple = Color3.fromRGB(215, 77, 255),
	Orange = Color3.fromRGB(255, 159, 48),
	Red = Color3.fromRGB(252, 23, 23),
	Gold = Color3.fromRGB(255, 207, 48),
	Panel = Color3.fromRGB(48, 48, 58),
	PanelDark = Color3.fromRGB(30, 30, 38),
	Locked = Color3.fromRGB(95, 95, 105),
	White = Color3.new(1, 1, 1),
	Black = Color3.new(0, 0, 0),
	Money = Color3.fromRGB(80, 235, 60),
}

---------------------------------------------------------------------
-- Основа
---------------------------------------------------------------------

-- Создать объект: Kit.new("Frame", { Size = ..., Parent = ... })
function Kit.new(className, props)
	local instance = Instance.new(className)
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
	end
	local parent = props.Parent
	for key, value in pairs(props) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	instance.Parent = parent
	return instance
end

function Kit.Corner(parent, radius)
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

-- Обводка рамки (Border) или текста (Contextual)
function Kit.Stroke(parent, thickness, color, border)
	return Kit.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Kit.Colors.Black,
		ApplyStrokeMode = border and Enum.ApplyStrokeMode.Border or Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

-- Картинка из UIAssets. Если Id ещё не вписан — пусто.
function Kit.Image(name)
	return UIAssets.Images[name] or ""
end

-- Чуть светлее или темнее цвет
function Kit.Shade(color, amount)
	local target = amount > 0 and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
	return color:Lerp(target, math.abs(amount))
end

-- Текст с чёрной обводкой — как во всех симуляторах Roblox
function Kit.Text(props)
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = props.Font or Kit.Font,
		Text = props.Text or "",
		TextColor3 = props.Color or Kit.Colors.White,
		TextScaled = true,
		TextXAlignment = props.AlignX or Enum.TextXAlignment.Center,
		TextYAlignment = props.AlignY or Enum.TextYAlignment.Center,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
		Active = false,
		Parent = props.Parent,
	})
	if props.Stroke ~= false then
		Kit.Stroke(label, props.StrokeThickness or 3)
	end
	return label
end

-- Картинка-иконка. Если картинки нет — показывает запасной текст (эмодзи).
function Kit.Icon(props)
	local id = Kit.Image(props.Image)
	if id == "" and props.Fallback then
		return Kit.Text({
			Text = props.Fallback, Size = props.Size, Position = props.Position,
			AnchorPoint = props.AnchorPoint, ZIndex = props.ZIndex, Parent = props.Parent,
			Font = Enum.Font.GothamBold,
		})
	end
	return Kit.new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = id,
		ImageColor3 = props.Color or Kit.Colors.White,
		ScaleType = Enum.ScaleType.Fit,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
		Active = false,
		Parent = props.Parent,
	})
end

-- Фон из "кубиков" (pattern_studs) поверх цветной подложки
function Kit.Studs(parent, transparency)
	local id = Kit.Image("pattern_studs")
	if id == "" then
		return nil
	end
	return Kit.new("ImageLabel", {
		Name = "Studs",
		BackgroundTransparency = 1,
		Image = id,
		ImageTransparency = transparency or 0.75,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(64, 64),
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = parent.ZIndex,
		Parent = parent,
	})
end

-- Свечение за предметом (glow_flare): белое, подкрашивается в color и мягко
-- "дышит" (то ярче, то тусклее). Не вращается: повёрнутые элементы Roblox
-- не обрезает по краю карточки, и свечение вылезало бы за окно.
-- Создавать ДО иконки предмета — тогда оно окажется под ней.
-- props: Size, Position, AnchorPoint, Color, Transparency, ZIndex, Parent
local glows = {}

function Kit.Glow(props)
	local id = Kit.Image("glow_flare")
	if id == "" then
		return nil
	end
	local glow = Kit.new("ImageLabel", {
		Name = "Glow",
		BackgroundTransparency = 1,
		Image = id,
		ImageColor3 = props.Color or Kit.Colors.White,
		ImageTransparency = props.Transparency or 0.3,
		ScaleType = Enum.ScaleType.Fit,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		Active = false,
		ZIndex = props.ZIndex or 12,
		Parent = props.Parent,
	})
	glows[glow] = props.Transparency or 0.3
	glow.Destroying:Connect(function()
		glows[glow] = nil
	end)
	return glow
end

-- Все свечения "дышат" одновременно
RunService.RenderStepped:Connect(function()
	local wave = 0.08 * math.sin(os.clock() * 2)
	for glow, base in pairs(glows) do
		glow.ImageTransparency = math.clamp(base + wave, 0, 1)
	end
end)

-- Градиент карточки товара: светлый верх, насыщенная середина, тёмный низ
function Kit.CardGradient(parent, color)
	return Kit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Kit.Shade(color, 0.45)),
			ColorSequenceKeypoint.new(0.45, color),
			ColorSequenceKeypoint.new(1, Kit.Shade(color, -0.35)),
		}),
		Rotation = 90,
		Parent = parent,
	})
end

-- Объёмная заливка: сверху светлее, снизу темнее
function Kit.Gloss(parent, color)
	return Kit.new("UIGradient", {
		Color = ColorSequence.new(Kit.Shade(color, 0.25), Kit.Shade(color, -0.15)),
		Rotation = 90,
		Parent = parent,
	})
end

---------------------------------------------------------------------
-- Кнопки
---------------------------------------------------------------------

-- Лёгкая анимация нажатия: кнопка чуть сжимается
local function addPress(button)
	local scale = Kit.new("UIScale", { Parent = button })
	local info = TweenInfo.new(0.08)
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, info, { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, info, { Scale = 0.93 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
end

-- Цветная кнопка с иконкой и/или текстом.
-- props: Size, Position, AnchorPoint, Color, Text, Image, Fallback, OnClick, Parent, TextColor
function Kit.Button(props)
	local color = props.Color or Kit.Colors.Green
	local button = Kit.new("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(200, 70),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	Kit.Corner(button, props.Corner or 8)
	Kit.Stroke(button, props.BorderThickness or 4, Kit.Shade(color, -0.55), true)
	Kit.Gloss(button, color)
	if props.Studs ~= false then
		local studs = Kit.Studs(button, 0.85)
		if studs then
			Kit.Corner(studs, props.Corner or 8)
		end
	end

	local hasImage = props.Image ~= nil
	local hasText = props.Text ~= nil
	if hasImage then
		Kit.Icon({
			Image = props.Image,
			Fallback = props.Fallback,
			Size = hasText and UDim2.new(0, button.Size.Y.Offset * 0.85, 0.85, 0) or UDim2.fromScale(0.85, 0.85),
			Position = hasText and UDim2.new(0, 8, 0.5, 0) or UDim2.fromScale(0.5, 0.5),
			AnchorPoint = hasText and Vector2.new(0, 0.5) or Vector2.new(0.5, 0.5),
			ZIndex = button.ZIndex + 1,
			Parent = button,
		})
	end
	if hasText then
		local left = hasImage and button.Size.Y.Offset * 0.85 + 12 or 8
		button:SetAttribute("TextLeft", left)
		Kit.Text({
			Text = props.Text,
			Color = props.TextColor,
			Size = UDim2.new(1, -left - 8, 0.7, 0),
			Position = UDim2.new(0, left, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = button.ZIndex + 1,
			Parent = button,
		}).Name = "Label"
	end

	addPress(button)
	if props.OnClick then
		button.Activated:Connect(props.OnClick)
	end
	return button
end

-- Поменять текст кнопки, сделанной Kit.Button
function Kit.SetButtonText(button, text)
	local label = button:FindFirstChild("Label")
	if label then
		label.Text = text
	end
end

---------------------------------------------------------------------
-- Масштаб под экран
---------------------------------------------------------------------

-- Вешает на frame UIScale, который подгоняет размер под экран.
-- Всё рисуется для 1920x1080, на телефоне — уменьшается.
function Kit.AutoScale(frame)
	local scale = Kit.new("UIScale", { Parent = frame })
	local camera = workspace.CurrentCamera
	local function update()
		local view = camera.ViewportSize
		scale.Scale = math.clamp(math.min(view.X / 1920, view.Y / 1080), 0.4, 1.3)
	end
	update()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return scale
end

---------------------------------------------------------------------
-- Окна
---------------------------------------------------------------------

local windows = {} -- все окна: одновременно открыто только одно

local stripePattern = {
	{ 0.48, 0.05 }, { 0.56, 0.02 }, { 0.62, 0.05 }, { 0.7, 0.02 },
}

-- Окно с цветным заголовком, кнопкой X и тёмным фоном с "кубиками".
-- Возвращает таблицу: Frame, Body (куда класть содержимое), Open, Close, Toggle, IsOpen
function Kit.Window(screen, props)
	local color = props.Color or Kit.Colors.Green
	local size = props.Size or Vector2.new(1160, 640)

	local holder = Kit.new("Frame", {
		Name = props.Name or "Window",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		Visible = false,
		Active = false,
		ZIndex = 10,
		Parent = screen,
	})
	Kit.AutoScale(holder)

	-- Тёмное тело окна
	local frame = Kit.new("Frame", {
		Name = "Frame",
		BackgroundColor3 = Kit.Colors.PanelDark,
		Size = UDim2.fromScale(1, 1),
		Active = true, -- окно не пропускает клики в мир под собой
		ZIndex = 10,
		Parent = holder,
	})
	Kit.Corner(frame, 10)
	Kit.Stroke(frame, 5, Kit.Colors.Black, true)
	Kit.Studs(frame, 0.9)

	-- Заголовок
	local titleBar = Kit.new("Frame", {
		Name = "Title",
		BackgroundColor3 = color,
		Size = UDim2.new(1, 0, 0, 92),
		Active = false,
		ClipsDescendants = true,
		ZIndex = 11,
		Parent = frame,
	})
	Kit.Corner(titleBar, 10)
	Kit.Stroke(titleBar, 4, Kit.Shade(color, -0.55), true)
	Kit.Gloss(titleBar, color)
	Kit.Studs(titleBar, 0.85)
	-- Наклонные блики, как на стекле
	for _, stripe in ipairs(stripePattern) do
		Kit.new("Frame", {
			BackgroundColor3 = Kit.Colors.White,
			BackgroundTransparency = 0.75,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(stripe[1], 0.5),
			Size = UDim2.new(stripe[2], 0, 2, 0),
			Rotation = 35,
			Active = false,
			ZIndex = 11,
			Parent = titleBar,
		})
	end
	Kit.Text({
		Text = props.Title,
		Size = UDim2.new(0.6, 0, 0.62, 0),
		Position = UDim2.new(0, 26, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		AlignX = Enum.TextXAlignment.Left,
		StrokeThickness = 4,
		ZIndex = 12,
		Parent = titleBar,
	})

	local window = { Frame = holder }

	-- Кнопка X. Modal = true: пока окно открыто, курсор свободен
	local close = Kit.Button({
		Name = "Close",
		Text = "X",
		Color = Kit.Colors.Red,
		Size = UDim2.fromOffset(76, 72),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Studs = false,
		ZIndex = 13,
		Parent = titleBar,
		OnClick = function()
			window.Close()
		end,
	})
	close.Modal = true
	local label = close:FindFirstChild("Label")
	if label then
		label.Size = UDim2.fromScale(0.8, 0.8)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
	end

	-- Место под содержимое
	window.Body = Kit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 108),
		Size = UDim2.new(1, -36, 1, -124),
		Active = false,
		ZIndex = 11,
		Parent = frame,
	})

	local openScale = Kit.new("UIScale", { Parent = frame })
	local onOpen = {}

	function window.IsOpen()
		return holder.Visible
	end

	function window.Open()
		for _, other in ipairs(windows) do
			if other ~= window and other.IsOpen() then
				other.Close()
			end
		end
		holder.Visible = true
		openScale.Scale = 0.85
		TweenService:Create(openScale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		for _, callback in ipairs(onOpen) do
			task.spawn(callback)
		end
	end

	function window.Close()
		holder.Visible = false
	end

	function window.Toggle()
		if window.IsOpen() then
			window.Close()
		else
			window.Open()
		end
	end

	-- Что сделать при каждом открытии (обновить данные)
	function window.OnOpen(callback)
		table.insert(onOpen, callback)
	end

	table.insert(windows, window)
	return window
end

-- Карточка: цветной прямоугольник с рамкой и "кубиками"
function Kit.Card(props)
	local color = props.Color or Kit.Colors.Blue
	local card = Kit.new("Frame", {
		Name = props.Name or "Card",
		BackgroundColor3 = color,
		Size = props.Size or UDim2.fromOffset(330, 230),
		LayoutOrder = props.LayoutOrder or 0,
		Active = false,
		ZIndex = props.ZIndex or 12,
		Parent = props.Parent,
	})
	Kit.Corner(card, 8)
	Kit.Stroke(card, 4, Kit.Shade(color, -0.6), true)
	Kit.CardGradient(card, color)
	Kit.Studs(card, 0.85)
	card.ClipsDescendants = true -- свечение не вылезает за карточку
	return card
end

function Kit.LocalPlayer()
	return Players.LocalPlayer
end

return Kit
