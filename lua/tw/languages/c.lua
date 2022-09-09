local C = {}

function C.configure_lsp(on_attach)
  return {
    on_attach = on_attach,
    flags = {
      debounce_text_changes = 150,
    },
    init_options = {
      compilationDatabaseDirectory = "build";
      index = {
        threads = 0;
      };
      clang = {
        excludeArgs = { "-frounding-math"} ;
      };
    }
  }
end

return C
