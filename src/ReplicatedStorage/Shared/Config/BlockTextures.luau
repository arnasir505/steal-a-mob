-- Id картинок-текстур для блочного декора карты (tools/BlockWorld.lua).
-- Сами картинки — в папке BlockTextures (их рисует tools/make_block_textures.ps1).
--
-- Как получить Id: в Studio View -> Asset Manager -> Bulk Import, выбери картинки,
-- потом правой кнопкой по картинке -> Copy ID to Clipboard и вставь число сюда.
-- 0 — без текстуры, блок будет просто цветным.
-- После изменения запусти tools/BlockWorld.lua ещё раз, чтобы текстуры встали.

return {
	GrassTop = 0,
	Dirt = 0,
	Stone = 0,
	Log = 0,
	Leaves = 0,
	BirchLog = 0,
	StoneBrick = 0,
	Path = 0,
	Sand = 0,
	Sandstone = 0,
	Snow = 0,
	Ice = 0,
	Hellrock = 0,
	Obsidian = 0,
	Hay = 0,
	Cactus = 0,
}
