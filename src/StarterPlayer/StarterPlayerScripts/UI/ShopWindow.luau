-- ShopWindow: магазин. Вкладки справа от окна:
--   Featured — все геймпассы;
--   Speed    — x2 скорость и пакеты скорости;
--   Money    — x2 деньги и пакеты денег (сумма считается от дохода игрока);
--   Eggs     — x2 вылупление и мгновенное вылупление;
--   Trails   — трейлы за игровые деньги.
-- Клиент только просит: покупку открывает и выдаёт сервер (ProductService, TrailService).

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Products = require(ReplicatedStorage.Shared.Config.Products)

local Kit = require(script.Parent.Kit)

local ShopWindow = {}

local TAB_ORDER = { "Featured", "Speed", "Money", "Eggs", "Trails" }
local TABS = {
	Featured = { Image = "icon_featured", Fallback = "🏷" },
	Speed = { Image = "icon_speed", Fallback = "👟" },
	Money = { Image = "icon_money", Fallback = "💵" },
	Eggs = { Image = "icon_eggs", Fallback = "🥚" },
	Trails = { Image = "trail_runner", Fallback = "✨" },
}

-- Как выглядят геймпассы
local PASSES = {
	X2Speed = { Title = "DOUBLE Your SPEED", Image = "shop_x2_speed", Color = Kit.Colors.Blue },
	X2Money = { Title = "DOUBLE Your MONEY", Image = "shop_x2_money", Color = Kit.Colors.Green },
	X2Hatch = { Title = "HATCH x2 FASTER", Image = "shop_x2_hatch", Color = Kit.Colors.Orange },
}

-- Как выглядят продукты
local PRODUCTS = {
	Speed200K = { Image = "shop_speed_small", Color = Kit.Colors.Blue },
	Speed1M = { Image = "shop_speed_big", Color = Kit.Colors.Blue },
	Money30Min = { Image = "shop_money_small", Color = Kit.Colors.Green },
	Money3Hours = { Image = "shop_money_big", Color = Kit.Colors.Green },
	InstantHatch = { Image = "shop_instant_hatch", Color = Kit.Colors.Orange },
}

local PAGES = {
	Featured = { Passes = { "X2Speed", "X2Money", "X2Hatch" }, Products = {} },
	Speed = { Passes = { "X2Speed" }, Products = { "Speed200K", "Speed1M" } },
	Money = { Passes = { "X2Money" }, Products = { "Money30Min", "Money3Hours" } },
	Eggs = { Passes = { "X2Hatch" }, Products = { "InstantHatch" } },
}

---------------------------------------------------------------------
-- Цены в Robux
---------------------------------------------------------------------

local priceCache = {} -- [infoType .. id] = цена

-- Настоящая цена с сайта Roblox. Пока продукт не создан — подсказка из конфига.
local function priceText(config, infoType, callback)
	if not config.Id or config.Id == 0 then
		callback(config.PriceHint and (Kit.Robux .. config.PriceHint) or "Soon")
		return
	end
	local key = tostring(infoType) .. config.Id
	if priceCache[key] then
		callback(Kit.Robux .. priceCache[key])
		return
	end
	callback(Kit.Robux .. "...")
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, config.Id, infoType)
		local price = ok and info and info.PriceInRobux
		if price then
			priceCache[key] = price
			callback(Kit.Robux .. price)
		else
			callback(config.PriceHint and (Kit.Robux .. config.PriceHint) or "Buy")
		end
	end)
end

---------------------------------------------------------------------
-- Карточки
---------------------------------------------------------------------

-- Широкий баннер геймпасса: картинка, заголовок, "x1 > x2", кнопка
local function passBanner(parent, player, passName, order)
	local look = PASSES[passName]
	local pass = Products.GamePasses[passName]
	local card = Kit.Card({ Color = look.Color, Size = UDim2.new(1, -12, 0, 190), LayoutOrder = order, Parent = parent })

	Kit.Glow({ Size = UDim2.fromOffset(380, 380), Position = UDim2.fromOffset(101, 95), ZIndex = 12, Parent = card })
	Kit.Icon({ Image = look.Image, Fallback = "⭐", Size = UDim2.fromOffset(170, 170), Position = UDim2.fromOffset(16, 10), ZIndex = 13, Parent = card })
	Kit.Text({ Text = look.Title, Size = UDim2.new(0.55, 0, 0, 56), Position = UDim2.new(0.5, 0, 0, 14), AnchorPoint = Vector2.new(0.5, 0), StrokeThickness = 4, ZIndex = 13, Parent = card })
	Kit.Text({ Text = "x1  ▶  x2", Color = Kit.Colors.Gold, Size = UDim2.new(0.4, 0, 0, 80), Position = UDim2.new(0.5, 0, 0, 78), AnchorPoint = Vector2.new(0.5, 0), StrokeThickness = 5, ZIndex = 13, Parent = card })
	Kit.Text({ Text = pass.Description or "", Size = UDim2.new(0.55, 0, 0, 26), Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 13, Parent = card })

	local button = Kit.Button({
		Text = "...", Color = Kit.Colors.Green, Size = UDim2.fromOffset(210, 84),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0), ZIndex = 13, Parent = card,
		OnClick = function()
			if not player:GetAttribute("Pass_" .. passName) then
				Remotes.Event("BuyPass"):FireServer(passName)
			end
		end,
	})

	local function refresh()
		if player:GetAttribute("Pass_" .. passName) then
			Kit.SetButtonText(button, "Owned")
			button.BackgroundColor3 = Kit.Colors.Locked
		else
			button.BackgroundColor3 = Kit.Colors.Green
			priceText(pass, Enum.InfoType.GamePass, function(text)
				Kit.SetButtonText(button, text)
			end)
		end
	end
	player:GetAttributeChangedSignal("Pass_" .. passName):Connect(refresh)
	refresh()
end

-- Что даёт продукт — текст на карточке
local function productAmount(player, productName)
	local product = Products.DevProducts[productName]
	if product.Type == "Speed" then
		return "+" .. Format.Number(product.Amount) .. " SPEED"
	elseif product.Type == "MoneyMinutes" then
		local income = player:GetAttribute("IncomePerSecond") or 0
		return "+$" .. Format.Number(Formulas.MoneyPack(income, product.Minutes, product.MinMoney))
	elseif product.Type == "InstantHatch" then
		local charges = player:GetAttribute("InstantHatches") or 0
		return charges > 0 and ("Instant Hatch (" .. charges .. ")") or "Instant Hatch"
	end
	return product.DisplayName or productName
end

local function productCard(parent, player, productName, order)
	local look = PRODUCTS[productName]
	local product = Products.DevProducts[productName]
	local card = Kit.Card({ Color = look.Color, Size = UDim2.fromOffset(340, 260), LayoutOrder = order, Parent = parent })

	Kit.Glow({ Size = UDim2.fromOffset(360, 360), Position = UDim2.new(0.5, 0, 0, 83), ZIndex = 12, Parent = card })
	Kit.Icon({ Image = look.Image, Fallback = "🎁", Size = UDim2.fromOffset(150, 150), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 13, Parent = card })
	local amount = Kit.Text({ Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0.5, 0, 0, 152), AnchorPoint = Vector2.new(0.5, 0), StrokeThickness = 4, ZIndex = 14, Parent = card })
	if product.Type == "MoneyMinutes" then
		Kit.Text({ Text = product.DisplayName or "", Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0.5, 0, 0, 190), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 14, Parent = card })
	end

	local button = Kit.Button({
		Text = "...", Color = Kit.Colors.Green, Size = UDim2.new(0, 290, 0, 50),
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), ZIndex = 14, Parent = card,
		OnClick = function()
			Remotes.Event("BuyProduct"):FireServer(productName)
		end,
	})
	priceText(product, Enum.InfoType.Product, function(text)
		Kit.SetButtonText(button, text)
	end)

	local function refresh()
		amount.Text = productAmount(player, productName)
	end
	player:GetAttributeChangedSignal("IncomePerSecond"):Connect(refresh)
	player:GetAttributeChangedSignal("InstantHatches"):Connect(refresh)
	refresh()
end

-- Страница с баннерами геймпассов и сеткой продуктов
local function storePage(parent, player, page)
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 12,
		Parent = parent,
	})
	Kit.new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = scroll })
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = scroll })

	for index, passName in ipairs(page.Passes) do
		passBanner(scroll, player, passName, index)
	end
	if #page.Products > 0 then
		local grid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 100, Active = false, Parent = scroll })
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(340, 260), CellPadding = UDim2.fromOffset(16, 16), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for index, productName in ipairs(page.Products) do
			productCard(grid, player, productName, index)
		end
	end
	return scroll
end

---------------------------------------------------------------------
-- Трейлы
---------------------------------------------------------------------

local function trailCard(parent, player, trailId, order)
	local trail = Items.Trails[trailId]
	local card = Kit.Card({ Color = trail.Color, Size = UDim2.fromOffset(320, 470), LayoutOrder = order, Parent = parent })

	Kit.Text({ Text = trail.DisplayName, Size = UDim2.new(1, -20, 0, 46), Position = UDim2.new(0.5, 0, 0, 12), AnchorPoint = Vector2.new(0.5, 0), StrokeThickness = 4, ZIndex = 13, Parent = card })
	Kit.Glow({ Size = UDim2.fromOffset(520, 520), Position = UDim2.new(0.5, 0, 0, 190), ZIndex = 12, Parent = card })
	Kit.Icon({ Image = "trail_runner", Fallback = "🏃", Color = Kit.Shade(trail.Color, 0.35), Size = UDim2.fromOffset(280, 260), Position = UDim2.new(0.5, 0, 0, 60), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 13, Parent = card })

	local multBox = Kit.new("Frame", { BackgroundColor3 = Kit.Colors.Black, BackgroundTransparency = 0.45, Size = UDim2.new(1, -30, 0, 54), Position = UDim2.new(0.5, 0, 0, 330), AnchorPoint = Vector2.new(0.5, 0), Active = false, ZIndex = 13, Parent = card })
	Kit.Corner(multBox, 6)
	Kit.Text({ Text = "x" .. trail.TreadmillMult .. " Treadmill", Color = Kit.Colors.Money, Size = UDim2.fromScale(0.9, 0.75), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 14, Parent = multBox })

	local button = Kit.Button({
		Text = "...", Color = Kit.Colors.Green, Size = UDim2.new(1, -30, 0, 62),
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), ZIndex = 14, Parent = card,
		OnClick = function()
			local owned = player:GetAttribute("Trail_" .. trailId)
			if owned then
				local equipped = player:GetAttribute("EquippedTrail") == trailId
				Remotes.Event("EquipTrail"):FireServer(equipped and "" or trailId)
			elseif not trail.Seasonal then
				Remotes.Event("BuyTrail"):FireServer(trailId)
			end
		end,
	})

	local function refresh()
		local owned = player:GetAttribute("Trail_" .. trailId)
		local equipped = player:GetAttribute("EquippedTrail") == trailId
		if equipped then
			Kit.SetButtonText(button, "Equipped")
			button.BackgroundColor3 = Kit.Colors.Locked
		elseif owned then
			Kit.SetButtonText(button, "Equip")
			button.BackgroundColor3 = Kit.Colors.Blue
		elseif trail.Seasonal then
			Kit.SetButtonText(button, "Calendar reward")
			button.BackgroundColor3 = Kit.Colors.Locked
		else
			Kit.SetButtonText(button, "$" .. Format.Number(trail.Price))
			button.BackgroundColor3 = Kit.Colors.Green
		end
	end
	player:GetAttributeChangedSignal("Trail_" .. trailId):Connect(refresh)
	player:GetAttributeChangedSignal("EquippedTrail"):Connect(refresh)
	refresh()
end

local function trailPage(parent, player)
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ZIndex = 12,
		Parent = parent,
	})
	Kit.new("UIListLayout", { Padding = UDim.new(0, 16), FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = scroll })

	-- По цене: дешёвые слева, сезонные в конце
	local ids = {}
	for trailId in pairs(Items.Trails) do
		table.insert(ids, trailId)
	end
	table.sort(ids, function(a, b)
		local ta, tb = Items.Trails[a], Items.Trails[b]
		if (ta.Seasonal or false) ~= (tb.Seasonal or false) then
			return not ta.Seasonal
		end
		return ta.Price < tb.Price
	end)
	for index, trailId in ipairs(ids) do
		trailCard(scroll, player, trailId, index)
	end
	return scroll
end

---------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------

function ShopWindow.Build(screen, player)
	local window = Kit.Window(screen, { Name = "Shop", Title = "Shop", Color = Kit.Colors.Green })

	local pages = {}
	for _, name in ipairs(TAB_ORDER) do
		local page = name == "Trails" and trailPage(window.Body, player) or storePage(window.Body, player, PAGES[name])
		page.Visible = false
		pages[name] = page
	end

	-- Вкладки справа от окна
	local tabs = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(1, 18, 0, 100),
		Size = UDim2.new(0, 150, 1, -100),
		Active = false,
		Parent = window.Frame,
	})
	Kit.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabs })

	local labels = {}
	local current

	local function show(name)
		current = pages[name] and name or "Featured"
		for pageName, page in pairs(pages) do
			page.Visible = pageName == current
		end
		for tabName, label in pairs(labels) do
			label.TextColor3 = tabName == current and Kit.Colors.Gold or Kit.Colors.White
		end
	end

	for index, name in ipairs(TAB_ORDER) do
		local tab = Kit.new("TextButton", {
			Name = name, Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
			Size = UDim2.fromOffset(150, 110), LayoutOrder = index, Parent = tabs,
		})
		Kit.Icon({ Image = TABS[name].Image, Fallback = TABS[name].Fallback, Size = UDim2.fromOffset(84, 84), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0), Parent = tab })
		labels[name] = Kit.Text({ Text = name, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 1, -34), Parent = tab })
		tab.Activated:Connect(function()
			show(name)
		end)
	end
	show("Featured")

	return {
		Window = window,
		-- Открыть магазин на нужной вкладке
		Open = function(pageName)
			show(pageName)
			window.Open()
		end,
	}
end

return ShopWindow
