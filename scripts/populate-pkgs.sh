#!/bin/sh

set -xe

cabal update

mkdir     -p pkgs
stack2nix -o pkgs/cardano-sl.nix          --system-ghc --revision 969dd3e0ba23f0d2ba50d0cc66d4aee40a4e7572 https://github.com/input-output-hk/cardano-sl.git

# stalled by: https://issues.serokell.io/issue/DEVOPS-137
# stack2nix -o pkgs/cardano-sl-explorer.nix --system-ghc                                                     https://github.com/input-output-hk/cardano-sl-explorer.git
