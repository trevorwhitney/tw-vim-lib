{
  description = "Neovim configured just how I like it";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    flake-utils.url = "github:numtide/flake-utils";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self
    , flake-utils
    , nixpkgs
    , nixpkgs-unstable
    }: flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ]
      (system:
      let
        unstable = import nixpkgs-unstable {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };

        pkgs =
          let
            base = import nixpkgs
              {
                inherit system;
                config = {
                  allowUnfree = true;
                };
              };
          in
          base // rec {
            inherit (unstable) claude-code delve go golangci-lint golangci-lint-langserver;
            callPackage = base.callPackage;
            jdtls = callPackage ./nix/packages/jdtls { };
            neovim = attrs: import ./nix/packages/neovim
              ({
                inherit self jdtls;
                inherit (base) lib fetchFromGitHub vimUtils neovimUtils;
                pkgs = base // { inherit jdtls claude-code golangci-lint golangci-lint-langserver; };
              } // attrs);
          };

        nodeJsPkg = pkgs.nodejs;
        goPkg = pkgs.go;
        delvePkg = pkgs.delve;
        golangciLintPkg = pkgs.golangci-lint;
        golangciLintLangServerPkg = pkgs.golangci-lint-langserver;
      in
      rec {
        inherit (pkgs) neovim;

        defaultPackage = pkgs.neovim {
          inherit goPkg nodeJsPkg delvePkg golangciLintPkg golangciLintLangServerPkg;
          withLspSupport = true;
        };

        packages = {
          neovim = defaultPackage;
        };

        devShells.default =
          let
            neovim = pkgs.neovim {
              inherit
                goPkg
                delvePkg
                golangciLintPkg
                golangciLintLangServerPkg
                nodeJsPkg;
              withLspSupport = true;
            };
          in

          pkgs.mkShell
            {
              EDITOR = "nvim";
              packages = [
                neovim
              ] ++ (with pkgs; [
                # General
                bashInteractive
                git
                gnumake
                luaPackages.luacheck
                nixpkgs-fmt
                statix
                stylua
                zip

                goPkg

                # NodeJS
                nodeJsPkg
                (yarn.override {
                  nodejs = nodeJsPkg;
                })

                # python with extra packages
                (
                  let
                    extra-python-packages = python-packages:
                      with python-packages; [
                        gyp
                      ];
                    python-with-packages = python311.withPackages
                      extra-python-packages;
                  in
                  python-with-packages
                )
              ]);
            };
      });
}
