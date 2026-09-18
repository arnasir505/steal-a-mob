-- Products: покупки за Robux.
-- Id = 0 значит "ещё не создано". Когда создашь геймпасс или продукт на сайте Roblox,
-- вставь сюда его настоящий Id. Цену в Robux ты указываешь на сайте, а не здесь
-- (поле PriceHint — только подсказка для тебя).
--
-- Для ориентира, цены в Steal an Egg (по данным игроков, могут меняться):
--   X2 Money — 399, X2 Growth Speed — 467, множитель скорости — около 499,
--   мгновенное вылупление — около 9 за яйцо.

local Products = {}

-- Геймпассы: покупаются один раз и действуют навсегда
Products.GamePasses = {
	X2Speed = { Id = 0, PriceHint = 499, Description = "x2 current speed and treadmill speed" },
	X2Hatch = { Id = 0, PriceHint = 467, Description = "Eggs hatch x2 faster" },
	X2Money = { Id = 0, PriceHint = 399, Description = "x2 money" },
}

-- Developer Products: можно покупать сколько угодно раз
-- MoneyMinutes — даёт доход игрока за указанное число минут (чтобы пакет не обесценивался)
Products.DevProducts = {
	Speed200K    = { Id = 0, Type = "Speed", Amount = 200000 },
	Speed1M      = { Id = 0, Type = "Speed", Amount = 1000000 },
	Money30Min   = { Id = 0, Type = "MoneyMinutes", Minutes = 30 },
	Money3Hours  = { Id = 0, Type = "MoneyMinutes", Minutes = 180 },
	InstantHatch = { Id = 0, Type = "InstantHatch" },
}

return Products
