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
	"jsonc",
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

local function configure()
	-- Install parsers for all configured languages
	require("nvim-treesitter").install(ensure_installed)

	-- Enable treesitter features for installed languages via FileType autocmd
	vim.api.nvim_create_autocmd("FileType", {
		pattern = ensure_installed,
		callback = function()
			vim.treesitter.start()
			vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
			vim.wo.foldmethod = "expr"
			vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		end,
	})
end

function M.setup()
	configure()
end

return M
