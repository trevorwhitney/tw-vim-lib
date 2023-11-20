{
  description = "Neovim configured just how I like it";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-23.05";
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
    flake-utils.lib.eachSystem [ "x86_64-linux" ]
      (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          inherit (nix) overlays;
          config = {
            allowUnfree = true;
          };
        };
      in
      {
        defaultPackage = pkgs.neovim;

        packages = {
          inherit (pkgs) neovim;
        };
      }) // {
      inherit (nix) overlay;
    };
}
