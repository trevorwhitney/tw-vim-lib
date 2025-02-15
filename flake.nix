{
  description = "Neovim configured just how I like it";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-24.11-darwin";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self
    , flake-utils
    , nixpkgs
    }:
    let
      nix = import ./nix {
        inherit self;
      };
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ]
      (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          inherit (nix) overlays;
          config = {
            allowUnfree = true;
          };
        };

        nodeJsPkg = pkgs.nodejs_20;
        goPkg = pkgs.go_1_23;
      in
      rec {
        inherit (pkgs) neovim;

        defaultPackage = pkgs.neovim {
          inherit goPkg nodeJsPkg;
          withLspSupport = true;
          useEslintDaemon = true;
        };

        packages = {
          neovim = defaultPackage;
        };

        devShells.default =
          let
            neovim = pkgs.neovim {
              inherit
                goPkg
                nodeJsPkg;
              withLspSupport = true;
              useEslintDaemon = true;
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
      }) // {
      inherit (nix) overlay;
    };
}
