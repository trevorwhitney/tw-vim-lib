{
  description = "Neovim configured just how I like it";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    flake-utils.url = "github:numtide/flake-utils";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self
    , flake-utils
    , nixpkgs
    , nixpkgs-unstable
    ,
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ] (
      system:
      let
        unstable = import nixpkgs-unstable {
          inherit system;
          config = {
            allowUnfree = true;
          };
          overlays = [
            (_final: prev: {
              # Upstream nixpkgs-unstable neovim-unwrapped 0.12.x ships flaky
              # treesitter functional tests (T159 "ignores overlapping injections"
              # races on the --listen socket and aborts the whole suite). The
              # failure has nothing to do with this flake, but it blocks the
              # devShell build entirely, so we skip the upstream test suite.
              neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (_old: {
                doCheck = false;
                doInstallCheck = false;
              });
            })
          ];
        };

        pkgs =
          let
            base = import nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
              };
            };
          in
          base
          // rec {
            inherit (unstable)
              claude-code
              delve
              gemini-cli
              go
              golangci-lint
              golangci-lint-langserver
              gopls
              ;
            callPackage = base.callPackage;
            jdtls = callPackage ./nix/packages/jdtls { };
            neovim =
              attrs:
              import ./nix/packages/neovim (
                {
                  inherit self jdtls;
                  inherit (base) lib fetchFromGitHub;
                  inherit (unstable) vimUtils;
                  pkgs = base // {
                    inherit
                      jdtls
                      claude-code
                      gemini-cli
                      golangci-lint
                      golangci-lint-langserver
                      ;
                    inherit (unstable) neovim-unwrapped wrapNeovimUnstable;
                  };
                }
                // attrs
              );
          };

        nodeJsPkg = pkgs.nodejs;
        goPkg = pkgs.go;
        delvePkg = pkgs.delve;
        golangciLintPkg = pkgs.golangci-lint;
        golangciLintLangServerPkg = pkgs.golangci-lint-langserver;
        goplsPkg = pkgs.gopls;
      in
      rec {
        inherit (pkgs) neovim;

        defaultPackage = pkgs.neovim {
          inherit
            goPkg
            nodeJsPkg
            delvePkg
            golangciLintPkg
            golangciLintLangServerPkg
            goplsPkg
            ;
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
                goplsPkg
                nodeJsPkg
                ;
              withLspSupport = true;
            };
          in

          pkgs.mkShell {
            EDITOR = "nvim";
            packages = [
              neovim
            ]
            ++ (with pkgs; [
              # General
              bashInteractive
              git
              gnumake
              lua5_3
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
                  extra-python-packages =
                    python-packages: with python-packages; [
                      gyp
                    ];
                  python-with-packages = python311.withPackages extra-python-packages;
                in
                python-with-packages
              )
            ]);
          };
      }
    );
}
