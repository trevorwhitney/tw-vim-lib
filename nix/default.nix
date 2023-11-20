{ self }: rec {
  overlay = import "${self}/nix/overlays/neovim.nix" {
    inherit self;
  };

  overlays = [
    overlay
  ];
}
