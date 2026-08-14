#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

./script/install-dep.sh --complgen

rm -rf .shell-completion && mkdir -p \
    .shell-completion/zsh \
    .shell-completion/fish \
    .shell-completion/bash

./.deps/cargo-root/bin/complgen aot ./grammar/commands-bnf-grammar.txt \
    --zsh-script .shell-completion/zsh/_aerospace-next \
    --fish-script .shell-completion/fish/aerospace-next.fish \
    --bash-script .shell-completion/bash/aerospace-next

# Check basic syntax
zsh -c 'autoload -Uz compinit; compinit; source ./.shell-completion/zsh/_aerospace-next'
fish -c 'source ./.shell-completion/fish/aerospace-next.fish'
bash -c 'source ./.shell-completion/bash/aerospace-next'
