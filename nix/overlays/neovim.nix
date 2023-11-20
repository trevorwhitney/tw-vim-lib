{self}: final: prev: {
  neovim = import ../packages/neovim {
    inherit self;
    inherit (prev) lib fetchFromGitHub vimUtils neovimUtils;
    pkgs = prev.extend (import ./jdtls.nix);
  };
}
