{ pkgs, ... }:
(pkgs.buildGoModule.override { go = pkgs.go_1_26 or pkgs.go; }) {
  pname = "agentd";
  version = "0.1.0";

  src = ../../../tools/agentd;
  subPackages = [ "cmd/agentd" ];

  vendorHash = "sha256-MXXxalxhx/cG9YInInMrk9vBuiV0K+Z575L0cHvhoGQ=";

  meta = {
    description = "Deterministic PR assistant daemon";
    mainProgram = "agentd";
  };
}
