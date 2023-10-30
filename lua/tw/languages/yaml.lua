
local Yaml = {}

function Yaml.configure_lsp(on_attach, capabilities)
  return {
    on_attach = on_attach,
    capabilities = capabilities,
    settings = {
      yaml = {
        keyOrdering = false,
      },
    },
  }
end

return Yaml
