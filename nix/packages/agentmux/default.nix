{ pkgs, ... }:
(pkgs.buildGoModule.override { go = pkgs.go_1_26 or pkgs.go; }) {
  pname = "agentmux";
  version = "0.1.0";

  src = ../../../tools/agentmux;

  vendorHash = "sha256-aUIGBb0ZCs9CmAB+KyJWcOUEYf6dQEFrQOkuq9qZ/QY=";

  meta = {
    description = "Cross-worktree agent overview TUI";
    mainProgram = "agentmux";
  };
}
