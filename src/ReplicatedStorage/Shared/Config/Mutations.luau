-- Mutations: мутации мобов. ВРЕМЕННЫЕ ЗНАЧЕНИЯ — заменим твоими.
-- Chance     — "вес" шанса при вылуплении (None = без мутации)
-- IncomeMult — множитель дохода

local Mutations = {}

Mutations.Data = {
	None    = { DisplayName = "",        Chance = 9700, IncomeMult = 1 },
	Golden  = { DisplayName = "Golden",  Chance = 250,  IncomeMult = 3 },
	Diamond = { DisplayName = "Diamond", Chance = 45,   IncomeMult = 8 },
	Rainbow = { DisplayName = "Rainbow", Chance = 5,    IncomeMult = 25 },
}

return Mutations
