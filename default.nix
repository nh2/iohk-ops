{ pkgs ? (import <nixpkgs> {})
, compiler ? pkgs.haskell.packages.ghc802
}:

with (import <nixpkgs/pkgs/development/haskell-modules/lib.nix> { inherit pkgs;});

let
  lib = import <nixpkgs/lib>;
  prodMode = drv: overrideCabal drv (drv: {
    doHaddock = false;
    patchPhase = ''
     export CSL_SYSTEM_TAG=linux64
    '';
    configureFlags = [ "-f-asserts" "-f-dev-mode" "-fwith-explorer" "--ghc-option=-DCONFIG=prod" "--ghc-option=-rtsopts" "--ghc-option=+RTS" "--ghc-option=+RTS" "--ghc-option=-A256m" "--ghc-option=-n2m" "--ghc-option=-RTS" "--ghc-options=-fno-specialise" ];
    # makeFlags = ["+RTS -A256m -n2m -RTS"];
  });
  socket-io-src = pkgs.fetchgit (removeAttrs (lib.importJSON ./pkgs/engine-io.json) ["date"]);
  cardano-sl-src = pkgs.fetchgit (removeAttrs (lib.importJSON ./pkgs/cardano-sl.json) ["date"]);

  overcabal = pkgs.haskell.lib.overrideCabal;
  hubsrc    =      repo: rev: sha256:       pkgs.fetchgit { url = "https://github.com/" + repo; rev = rev; sha256 = sha256; };
  overc     = old:                    args: overcabal old (oldAttrs: (oldAttrs // args));
  overhub   = old: repo: rev: sha256: args: overc old ({ src = hubsrc repo rev sha256; }       // args);
  overhage  = old: version:   sha256: args: overc old ({ version = version; sha256 = sha256; } // args);
in compiler.override {
  overrides = self: super: {
    # To generate these go to ./pkgs and run ./generate.sh
    universum = super.callPackage ./pkgs/universum.nix { };
    serokell-util = super.callPackage ./pkgs/serokell-util.nix { };
    acid-state = super.callPackage ./pkgs/acid-state.nix { };
    log-warper = super.callPackage ./pkgs/log-warper.nix { };
    ed25519 = dontCheck (super.callPackage ./pkgs/ed25519.nix { });
    rocksdb = super.callPackage ./pkgs/rocksdb-haskell.nix { rocksdb = pkgs.rocksdb; };
    kademlia = super.callPackage ./pkgs/kademlia.nix { };
    node-sketch = super.callPackage ./pkgs/time-warp-nt.nix { };
    cardano-report-server = super.callPackage ./pkgs/cardano-report-server.nix { };
    cardano-crypto = super.callPackage ./pkgs/cardano-crypto.nix { };
    plutus-prototype = super.callPackage ./pkgs/plutus-prototype.nix { };
    network-transport = super.callPackage ./pkgs/network-transport.nix { };
    network-transport-tcp = super.callPackage ./pkgs/network-transport-tcp.nix { };

    # servant-multipart needs servant 0.10
    servant = dontCheck super.servant_0_10;
    servant-docs = super.servant-docs_0_10;
    servant-server = dontCheck super.servant-server_0_10;
    servant-swagger = dontCheck super.servant-swagger_1_1_2_1;

    comonad       = dontCheck super.comonad;
    distributive  = dontCheck super.distributive;
    http-date     = dontCheck super.http-date;
    http-types    = dontCheck super.http-types;
    http2         = dontCheck super.http2;
    iproute       = dontCheck super.iproute;
    lens          = dontCheck super.lens;
    parsers       = dontCheck super.parsers;
    semigroupoids = dontCheck super.semigroupoids;
    swagger2      = dontCheck super.swagger2;
    turtle        = dontCheck super.turtle;
    unix-time     = dontCheck super.unix-time;

    cryptonite = super.cryptonite_0_23;
    cryptonite-openssl = overhage super.cryptonite-openssl "0.6" "19jhhz1ad5jw8zc7ia9bl77g7nw2g0qjk5nmz1zpngpvdg4rgjx8" {};

    ether = super.ether_0_5_0_0;    
    foundation = super.foundation_0_0_8;    
    memory = super.memory_0_14_5;
    transformers = super.transformers_0_5_4_0;
    transformers-lift = overhage super.transformers-lift_0_2_0_0 "0.2.0.1" "17g03r5hpnygx0c9ybr9za6208ay0cjvz47rkyplv1r9zcivzn0b" {};
    writer-cps-transformers = super.writer-cps-transformers_0_1_1_3;
    writer-cps-mtl = super.writer-cps-mtl_0_1_1_4;

    # sl-explorer fixes
    map-syntax = dontCheck super.map-syntax;
    snap = dontCheck super.snap;

    socket-io = super.callCabal2nix "socket-io" "${socket-io-src}/socket-io" {};
    engine-io = super.callCabal2nix "engine-io" "${socket-io-src}/engine-io" {};
    engine-io-wai = super.callCabal2nix "engine-io-wai" "${socket-io-src}/engine-io-wai" {};

    # TODO: https://github.com/NixOS/cabal2nix/issues/261
    cardano-sl-core = prodMode (super.callCabal2nix "cardano-sl-core" "${cardano-sl-src}/core" {});
    cardano-sl-db = prodMode (super.callCabal2nix "cardano-sl-db" "${cardano-sl-src}/db" {});
    cardano-sl-infra = prodMode (super.callCabal2nix "cardano-sl-infra" "${cardano-sl-src}/infra" {});
    cardano-sl-lrc = prodMode (super.callCabal2nix "cardano-sl-lrc" "${cardano-sl-src}/lrc" {});
    cardano-sl-update = prodMode (super.callCabal2nix "cardano-sl-update" "${cardano-sl-src}/update" {});
    cardano-sl-ssc = prodMode (super.callCabal2nix "cardano-sl-ssc" "${cardano-sl-src}/ssc" {});
    cardano-sl-godtossing = prodMode (super.callCabal2nix "cardano-sl-godtossing" "${cardano-sl-src}/godtossing" {});
    cardano-sl-explorer = prodMode (super.callPackage ./pkgs/cardano-sl-explorer.nix { });

    cardano-sl = prodMode (super.callCabal2nix "cardano-sl" cardano-sl-src {});
    cardano-sl-static = self.cardano-sl;
    cardano-report-server-static = self.cardano-report-server;
    cardano-sl-explorer-static = self.cardano-sl-explorer;

    #mkDerivation = args: super.mkDerivation (args // {
    #enableLibraryProfiling = false;
    #});
  };
}
