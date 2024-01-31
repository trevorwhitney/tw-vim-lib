{
  description = "Neovim configured just how I like it";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-23.11";
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

        nodeJsPkg = pkgs.nodejs_20;
        goPkg = pkgs.go_1_21;
      in
      {
        defaultPackage = pkgs.neovim;

        packages = {
          inherit (pkgs) neovim;
        };


        devShells.default = pkgs.mkShell
          {
            packages = with pkgs; [
              # General
              bashInteractive
              git
              gnumake
              zip

              # NodeJS
              nodeJsPkg
              (yarn.override {
                nodejs = nodeJsPkg;
              })

              (pkgs.neovim.override {
                inherit
                  goPkg
                  nodeJsPkg;
                withLspSupport = true;
                useEslintDaemon = true;
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

              # vs code
              (vscode-with-extensions.override {
                vscodeExtensions =
                  with vscode-extensions; [
                    github.copilot
                    asvetliakov.vscode-neovim
                    golang.go
                    stephlin.vscode-tmux-keybinding
                  ];
                # ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
                #   {
                #     name = "vscode-neovim";
                #     publisher = "asvetliakov";
                #     version = "1.5.0";
                #     sha256 = "Y74Fkq0Mz7I5EmU6gCrOo72ecZVOIS0Pk6jgX3tqir4=";
                #   }
                # ];
              })
            ];
          };
      }) // {
      inherit (nix) overlay;
    };
}
