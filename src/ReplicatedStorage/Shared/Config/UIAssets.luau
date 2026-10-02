-- UIAssets: картинки интерфейса.
--
-- Файлы лежат в папке UI_Assets (их нарезал tools/cut_ui_art.py из листов нейросети).
-- Как подключить картинку:
--   1. В Studio: View → Asset Manager → Bulk Import → выбери файлы из UI_Assets.
--   2. В Asset Manager → Images: правый клик по картинке → Copy ID to Clipboard.
--   3. Вставь число вместо 0 у картинки с тем же именем.
-- Пока стоит 0, интерфейс покажет вместо картинки простую заглушку.
--
-- ВАЖНО: нужен Id картинки (Image), а не наклейки (Decal). Asset Manager часто
-- даёт Id наклейки — с ним картинка не покажется. Перевести все Id разом:
-- вставь в Studio в Command Bar (View → Command Bar) эту строку и нажми Enter,
-- а из Output скопируй готовые строки сюда вместо старых:
--[[
local I=game:GetService("InsertService") local A=require(game.ReplicatedStorage.Shared.Config.UIAssets) local n={} for k in pairs(A.Images) do table.insert(n,k) end table.sort(n) for _,k in ipairs(n) do local d=tonumber(string.match(A.Images[k],"%d+")) if d then local ok,m=pcall(I.LoadAsset,I,d) local dc=ok and m:FindFirstChildWhichIsA("Decal",true) local img=dc and string.match(dc.Texture,"%d+") print(string.format("\t%s = id(%s),",k,img or "0")) if ok then m:Destroy() end end end
]]

local UIAssets = {}

local function id(number)
	return number ~= 0 and ("rbxassetid://" .. number) or ""
end

UIAssets.Images = {
	-- Кнопки на экране
	icon_shop = id(71559586932090),
	icon_index = id(136508712381567),
	icon_eggs = id(81418179216885),
	icon_mobs = id(121627323234383),
	icon_boost = id(92503242393634),
	icon_speed = id(100796124270073),
	icon_money = id(86650412177760),
	icon_featured = id(85883292667628),
	icon_gift = id(139359034501616),
	icon_drop = id(92674296326792),
	icon_night = id(121725470132830),
	icon_plus = id(119352496309903), -- "+" у скорости: магазин скорости
	icon_timer = id(100330839831704),

	-- Товары магазина
	shop_speed_small = id(94079460921932),
	shop_speed_big = id(110432911504291),
	shop_x2_speed = id(79364192763696),
	shop_money_small = id(101945550019470),
	shop_money_big = id(123170392273211),
	shop_x2_money = id(122169727390056),
	shop_instant_hatch = id(134899150823110),
	shop_x2_hatch = id(92392183748659),
	shop_lightning = id(88625269535321),

	-- Трейлы (одна белая фигурка, цвет задаётся в игре), биомы, фон окон
	trail_runner = id(82338875349140),
	biome_plains = id(105162285500535),
	biome_forest = id(0),
	biome_desert = id(0),
	biome_snow = id(0),
	biome_swamp = id(0),
	biome_underworld = id(0),
	biome_crystalcave = id(0),
	pattern_studs = id(73235366447601),

	-- Белое свечение за товарами, трейлами и мобами (красится под цвет карточки)
	glow_flare = id(84654787699113),
}

return UIAssets