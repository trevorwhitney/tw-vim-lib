local M = {}

local ensure_installed = {
	"bash",
	"bibtex",
	"c",
	"c_sharp",
	"clojure",
	"cmake",
	"comment",
	"commonlisp",
	"cpp",
	"css",
	"diff",
	"dockerfile",
	"dot",
	"elixir",
	"erlang",
	"fish",
	"go",
	"godot_resource",
	"gomod",
	"gowork",
	"graphql",
	"hcl",
	"hjson",
	"hocon",
	"html",
	"http",
	"java",
	"javascript",
	"jsdoc",
	"json",
	"json5",
	"jsonnet",
	"julia",
	"kotlin",
	"latex",
	"llvm",
	"lua",
	"make",
	"markdown",
	"markdown_inline",
	"nix",
	"perl",
	"php",
	"python",
	"ql",
	"query",
	"r",
	"regex",
	"ruby",
	"rust",
	"scala",
	"scheme",
	"scss",
	"todotxt",
	"toml",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
	"wgsl",
	"yaml",
}

-- Use a wildcard pattern so any filetype with a parser gets highlighting,
-- rather than trying to maintain a separate filetype-to-parser mapping.
-- pcall guards against parsers that haven't been compiled yet (first startup).
local function enable_treesitter_features()
	local ok = pcall(vim.treesitter.start)
	if ok then
		vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
		vim.wo.foldmethod = "expr"
		vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
end

local function configure()
	-- Install parsers for all configured languages
	require("nvim-treesitter").install(ensure_installed)

	-- Enable treesitter features for any filetype that has a parser available.
	-- Using "*" avoids parser-name vs filetype mismatches (e.g. c_sharp vs cs).
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "*",
		callback = enable_treesitter_features,
	})
end

function M.setup()
	configure()
end

return M
