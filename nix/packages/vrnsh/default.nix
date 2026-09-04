{ pkgs, neovim, ... }:
pkgs.writeShellApplication {
  name = "vrnsh";
  runtimeInputs = [ neovim ];
  text = builtins.readFile ../../../bin/vrnsh;
}
