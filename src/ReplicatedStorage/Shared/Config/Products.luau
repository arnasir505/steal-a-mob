-- Products: покупки за Robux. Выдачу товаров делает ProductService.
-- Id = 0 значит "ещё не создано". Когда создашь геймпасс или продукт на сайте Roblox
-- (Creator Dashboard → твоя игра → Monetization → Passes / Developer Products),
-- вставь сюда его настоящий Id. Цену в Robux ты указываешь на сайте, а не здесь
-- (поле PriceHint — только подсказка для тебя).
-- Имя продукта (ключ таблицы, например Money30Min) менять нельзя — по нему игра
-- понимает, что выдавать. DisplayName — для интерфейса.
--
-- Для ориентира, цены в Steal an Egg (по данным игроков, могут меняться):
--   X2 Money — 399, X2 Growth Speed — 467, множитель скорости — около 499,
--   мгновенное вылупление — около 9 за яйцо.

local Products = {}

-- Геймпассы: покупаются один раз и действуют навсегда
Products.GamePasses = {
	X2Speed = { Id = 0, PriceHint = 3, Description = "x2 current speed and treadmill speed" },
	X2Hatch = { Id = 0, PriceHint = 5, Description = "Eggs hatch x2 faster" },
	X2Money = { Id = 0, PriceHint = 8, Description = "x2 money" },
}

-- Developer Products: можно покупать сколько угодно раз.
--   Speed        — +Amount скорости
--   MoneyMinutes — доход игрока за Minutes минут (чтобы пакет не обесценивался),
--                  но не меньше MinMoney (ВРЕМЕННЫЕ ЧИСЛА)
--   InstantHatch — мгновенно вылупить одно яйцо (кнопка Hatch Now у яйца на участке)
Products.DevProducts = {
	Speed200K    = { Id = 0, Type = "Speed", Amount = 200000, DisplayName = "+200K Speed" },
	Speed1M      = { Id = 0, Type = "Speed", Amount = 1000000, DisplayName = "+1M Speed" },
	Money30Min   = { Id = 0, Type = "MoneyMinutes", Minutes = 30, MinMoney = 5000, DisplayName = "30 min of income" },
	Money3Hours  = { Id = 0, Type = "MoneyMinutes", Minutes = 180, MinMoney = 30000, DisplayName = "3 hours of income" },
	InstantHatch = { Id = 0, Type = "InstantHatch", PriceHint = 9, DisplayName = "Instant Hatch" },
}

return Products
