local very_lazy = require("tw.plugin-events").very_lazy()

return {
	{
		"MeanderingProgrammer/render-markdown.nvim",
		ft = "markdown",
		opts = { latex = { enabled = false } },
	},
	{ "HakonHarnes/img-clip.nvim", event = very_lazy },
}
