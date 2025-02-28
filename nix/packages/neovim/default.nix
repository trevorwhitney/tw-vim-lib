{ pkgs
, lib
, self
, vimUtils
, neovimUtils
, withLspSupport ? true
, nodeJsPkg ? pkgs.nodejs
, goPkg ? pkgs.go_1_23
, useEslintDaemon ? true
, extraPackages ? [ ]
, goBuildTags ? ""
, dapConfigurations ? {}
, ...
}:
let
  basePackages = with pkgs; [
    nodeJsPkg
    goPkg

    gcc
    gnumake
    gnutar

    nodePackages.markdownlint-cli
    nil
    nixpkgs-fmt
    statix

    claude-code
    (pkgs.callPackage ../change-background {
      inherit pkgs;
    })
  ];

  lspPackages = with pkgs;
  if withLspSupport then (lib.optionals stdenv.isDarwin [
      pngpaste
  ]) ++ [
    stylua
    jdtls

    ccls # c++ language server
    codespell
    delve
    gofumpt
    golangci-lint
    golangci-lint-langserver
    golines
    gopls
    gotools
    grafana-alloy
    helm-ls
    jsonnet-language-server
    lua-language-server
    marksman
    pprof
    prettierd
    pyright
    shellcheck
    shfmt
    terraform-ls
    typescript
    vale
    vim-language-server
    vim-vint
    vscode-langservers-extracted
    write-good
    yaml-language-server
    yamllint

    nodePackages.bash-language-server
    nodePackages.dockerfile-language-server-nodejs
    nodePackages.eslint
    nodePackages.eslint_d
    nodePackages.fixjson
    nodePackages.prettier
    nodePackages.typescript-language-server
    nodePackages.vscode-langservers-extracted

    lua53Packages.luacheck
    lua53Packages.jsregexp
    lua53Packages.tiktoken_core
    ] else [ ];

  treesitterPackages = with pkgs; [
    # TODO: not entirely sure which of these fixed it
    # but we did move to clang++, so maybe of the last 2?
    # TODO: libgcc was removed, replace with gcc.cc.libgcc if actually needed
    # libgcc
    libclang
    clangStdenv

    stdenv.cc
    tree-sitter
  ];

  packages = basePackages ++ treesitterPackages ++ lspPackages ++ extraPackages;

  extraMakeWrapperArgs = lib.optionalString (packages != [ ])
    ''--prefix PATH : "${lib.makeBinPath packages}"'';

  neovimConfig = neovimUtils.makeNeovimConfig
    {
      vimAlias = true;
      withRuby = true;
      withPython3 = true;

      # manually overridden in package
      withNodeJs = false;

      extraPython3Packages = ps: with ps; [ pynvim tiktoken ];
      plugins = with pkgs.vimPlugins; [
        packer-nvim
        (vimUtils.buildVimPlugin rec {
          pname = "tw-vim-lib";
          version = if (self ? rev) then self.rev else "dirty";
          src = self;
          meta.homepage = "https://github.com/trevorwhitney/tw-vim-lib";
          doCheck = false;
        })
      ];

      customRC = builtins.concatStringsSep "\n" (with pkgs; [
        "lua <<EOF"
        "require('tw').setup({"
      ] ++ (if withLspSupport then [
        "lsp_support = true,"
        "lua_ls_root = '${lua-language-server}',"
        "rocks_tree_root = '${lua53Packages.luarocks}',"
        "jdtls_home = '${jdtls}',"
        "use_eslint_daemon = ${lib.boolToString useEslintDaemon},"
        "go_build_tags = '${goBuildTags}',"
        "dap_configs = ${lib.generators.toLua {} dapConfigurations},"
      ] else [
        "lsp_support = false,"
      ]) ++ [
        "extra_path = {'${stdenv.cc}/bin', '${tree-sitter}/bin'},"
        "})"
        "EOF"
      ]);
    };
in
with pkgs; (wrapNeovimUnstable
  (neovim-unwrapped.override { nodejs = nodeJsPkg; })
  (neovimConfig // {
    wrapperArgs =
      (lib.escapeShellArgs neovimConfig.wrapperArgs) + " "
        + extraMakeWrapperArgs;
  }))
