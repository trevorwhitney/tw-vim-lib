#!/bin/bash


pack_path="$(grep packpath ~/.config/nvim/init.vim | cut -d '=' -f 2)"
vim_lib_path="${pack_path}/pack/home-manager/start/vimplugin-tw-vim-lib/"

sudo rsync -ar . "$vim_lib_path"



