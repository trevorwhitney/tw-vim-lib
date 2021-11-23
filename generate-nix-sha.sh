#!/bin/bash

sha256="$(nix-prefetch-url \
	--unpack https://github.com/trevorwhitney/tw-vim-lib/archive/main.tar.gz)"

cat <<EOF
{
  owner = "trevorwhitney";
  repo = "tw-vim-lib";
  rev = "main";
  sha256 = "${sha256}";
}
EOF
