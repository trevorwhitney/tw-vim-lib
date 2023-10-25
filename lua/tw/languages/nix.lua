local Nix = {}

function Nix.configure_lsp(on_attach, capabilities)
  return {
    on_attach = on_attach,
    capabilities = capabilities,
    settings = {
      ["nil"] = {
        nix = {
          flake = {
            autoArchive = true,
          },
        },
      },
    },
  }
end

return Nix
