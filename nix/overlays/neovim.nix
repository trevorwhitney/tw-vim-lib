{ self }: final: prev: {
  neovim = attrs: import ../packages/neovim
    ({
      inherit self;
      inherit (prev) lib fetchFromGitHub vimUtils neovimUtils;
      pkgs = prev.extend (import ./jdtls.nix);
    } // attrs);
}
