-- Mutations: мутации мобов. Выпадают в момент вылупления яйца, у яйца мутации нет.
--
-- Chance     — шанс В ПРОЦЕНТАХ (сумма = 100, поэтому число и есть процент).
--              Если сумма перестанет быть 100, шансы посчитаются по пропорции.
-- IncomeMult — множитель дохода
-- Color      — в какой цвет перекрасить модель моба. Если убрать поле,
--              модель останется как есть (пригодится, когда сделаешь
--              отдельные модели под мутации).
-- Material   — материал модели: металл блестит, Neon светится.
-- Announce   — показать сообщение всем игрокам сервера, когда такой моб вылупился.

local Mutations = {}

-- Порядок от обычного к редкому (для интерфейса и случайного выбора)
Mutations.Order = { "None", "Silver", "Golden", "Diamond", "Rainbow" }

Mutations.Data = {
	None    = { DisplayName = "",        Chance = 84,  IncomeMult = 1,  Announce = false },
	Silver  = { DisplayName = "Silver",  Chance = 10,  IncomeMult = 3,  Announce = false, Color = Color3.fromRGB(205, 210, 220), Material = Enum.Material.Metal },
	Golden  = { DisplayName = "Golden",  Chance = 4,   IncomeMult = 5,  Announce = false, Color = Color3.fromRGB(255, 200, 40),  Material = Enum.Material.Metal },
	Diamond = { DisplayName = "Diamond", Chance = 1.5, IncomeMult = 8,  Announce = true,  Color = Color3.fromRGB(120, 230, 255), Material = Enum.Material.Glass },
	Rainbow = { DisplayName = "Rainbow", Chance = 0.5, IncomeMult = 30, Announce = true,  Color = Color3.fromRGB(255, 90, 200),  Material = Enum.Material.Neon },
}

local totalChance = 0
for _, id in ipairs(Mutations.Order) do
	totalChance = totalChance + (Mutations.Data[id] and Mutations.Data[id].Chance or 0)
end

-- Данные мутации. Незнакомая или пустая мутация считается обычной (None).
function Mutations.Get(mutationId)
	return Mutations.Data[mutationId] or Mutations.Data.None
end

-- Настоящий шанс долей от 1 (0.005 = 0.5%)
function Mutations.SpawnChance(mutationId)
	local data = Mutations.Data[mutationId]
	if not data or totalChance <= 0 then
		return 0
	end
	return data.Chance / totalChance
end

return Mutations
