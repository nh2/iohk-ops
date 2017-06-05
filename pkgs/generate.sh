#!/usr/bin/env nix-shell
#! nix-shell -j 4 -i bash -p pkgs.cabal2nix pkgs.nix-prefetch-scripts
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/464c79ea9f929d1237dbc2df878eedad91767a72.tar.gz

set -xe

cabal2nix https://github.com/serokell/universum --no-check --revision 7fc58d5756ff44beac914b7a597d9cca36235ea3 > universum.nix
cabal2nix https://github.com/serokell/serokell-util.git --revision 1309ac5024fb0c62b56c3bd7d16feb0a318a2512 > serokell-util.nix
cabal2nix https://github.com/serokell/acid-state.git --revision 95fce1dbada62020a0b2d6aa2dd7e88eadd7214b > acid-state.nix
cabal2nix https://github.com/serokell/log-warper.git --revision cb3288415d40318e04ca920ff81ea4ea8e0380bd > log-warper.nix
cabal2nix https://github.com/serokell/kademlia.git --no-check --revision 92043c7e80e93aeb08212e8ce42c783edd9b2f80 > kademlia.nix
cabal2nix https://github.com/serokell/rocksdb-haskell.git --revision 4dfd8d61263d78a91168e86e8005eb9b7069389e > rocksdb-haskell.nix
cabal2nix https://github.com/serokell/time-warp-nt.git --no-check --revision 3fa7ccea4031a7424e77b63fd1f29e4d69b70b98 > time-warp-nt.nix

cabal2nix https://github.com/thoughtpolice/hs-ed25519.git --revision da4247b5b3420120e20451e6a252e2a2ca15b43c > ed25519.nix
cabal2nix https://github.com/serokell/network-transport.git --no-check --revision f2321a103f53f51d36c99383132e3ffa3ef1c401 > network-transport.nix
cabal2nix https://github.com/serokell/network-transport-tcp.git --no-check --revision a6c04c35f3a1d786bc5e57fd04cf3e2a043179f3 > network-transport-tcp.nix
cabal2nix https://github.com/input-output-hk/cardano-crypto --no-check --revision 96adbd5aa9a906859deddf170f8762a9ed85c0c9 > cardano-crypto.nix
cabal2nix https://github.com/input-output-hk/cardano-sl-explorer.git --no-check --revision 24cd9bf6b3b02efd9f81a4791a6f42de8ab23e8a > cardano-sl-explorer.nix

cabal2nix https://github.com/input-output-hk/cardano-report-server.git --revision 424e4ecacdf038a01542025dd1296bd272ce770d > cardano-report-server.nix
cabal2nix https://github.com/input-output-hk/plutus-prototype.git --revision e2e2711e6978002279b4d7c49cab1aff47a2fd43 > plutus-prototype.nix

cabal2nix https://github.com/int-index/ether.git --revision 0c0c26fc8a74b52949d0ad0b1432c0d684393e43 > ether.nix

# TODO: https://github.com/NixOS/cabal2nix/issues/261
nix-prefetch-git https://github.com/serokell/engine.io.git a594e402fd450f11ad60d09ddbd93db500000632 > engine-io.json
nix-prefetch-git https://github.com/input-output-hk/cardano-sl.git 1239a6a876fbbb970e836c8bc6bb72d781ba2fa9 > cardano-sl.json
