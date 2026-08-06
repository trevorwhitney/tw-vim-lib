{ pkgs, ... }:
(pkgs.buildGoModule.override { go = pkgs.go_1_26 or pkgs.go; }) {
  pname = "agentmux";
  version = "0.1.0";

  # src spans both modules so the go.mod replace on ../agentd resolves in the
  # build sandbox; modRoot keeps the build rooted at the agentmux module.
  src = ../../../tools;
  modRoot = "agentmux";

  vendorHash = "sha256-m++g0YIoIwOF8UzMRhz4d6cYVqeHkRbgCMIrk9ZjQdo=";

  meta = {
    description = "Cross-worktree agent overview TUI";
    mainProgram = "agentmux";
  };
}
