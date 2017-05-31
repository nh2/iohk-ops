{ pkgs ? (import <nixpkgs> {})
, compiler ? pkgs.haskell.packages.ghc802
}:

with (import <nixpkgs/pkgs/development/haskell-modules/lib.nix> { inherit pkgs;});

let
  lib = import <nixpkgs/lib>;
  prodMode = drv: overrideCabal drv (drv: {
    configureFlags = [ "-f-asserts" "-f-dev-mode"];
  });

  githubSrc     =      repo: rev: sha256:       pkgs.fetchgit  { url = "https://github.com/" + repo; rev = rev; sha256 = sha256; };
  overC         =                               pkgs.haskell.lib.overrideCabal;
  overCabal     = old:                    args: overC old (oldAttrs: (oldAttrs // args));
  overGithub    = old: repo: rev: sha256: args: overC old ({ src = githubSrc repo rev sha256; }     // args);
  overHackage   = old: version:   sha256: args: overC old ({ version = version; sha256 = sha256; } // args);

  cabal2nix     = overGithub compiler.cabal2nix "NixOS/cabal2nix"
                  "b6834fd420e0223d0d57f8f98caeeb6ac088be88" "1ia2iw137sza655b0hf4hghpmjbsg3gz3galpvr5pbbsljp26m6p" { version = "2.2.1"; };
  stack2nix     = dontCheck
                  (pkgs.haskellPackages.callCabal2nix "stack2nix"
                   (githubSrc "input-output-hk/stack2nix" "c27a9faa9ba2a7ffd162a38953a36caad15e6839" "1cmw7zq0sf5fr9sc4daf1jwlnjll9wjxqnww36dl9cbbj9ak0m77") {});
  ## Mostly stolen from: nixpkgs/pkgs/development/haskell-modules/make-package-set.nix : haskellSrc2nix
  stack2nixEmit = { name, src, sha256 ? null }:
    let
      sha256Arg = if isNull sha256 then "--sha256=" else ''--sha256="${sha256}"'';
    in pkgs.stdenv.mkDerivation {
      name = "stack2nix-${name}";
      buildInputs = [ stack2nix cabal2nix pkgs.nix pkgs.nix-prefetch-git pkgs.nix-prefetch-hg ];
      preferLocalBuild = true;
      phases = ["installPhase"];
      LANG = "en_US.UTF-8";
      LOCALE_ARCHIVE = pkgs.lib.optionalString pkgs.stdenv.isLinux "${pkgs.glibcLocales}/lib/locale/locale-archive";
      installPhase = ''
        export HOME="$TMP"
        mkdir -p "$out"
        stack2nix "${src}" -o "$out/default.nix"
      '';
  };
  callStack2nix = hpkgs: name: src: hpkgs.callPackage (stack2nixEmit { inherit src name; });

  socket-io-src = pkgs.fetchgit (removeAttrs (lib.importJSON ./pkgs/engine-io.json) ["date"]);
  cardano-sl-src = pkgs.fetchgit (removeAttrs (lib.importJSON ./pkgs/cardano-sl.json) ["date"]);

in compiler.override {
  overrides = self: super: {
    # To generate these go to ./pkgs and run ./generate.sh
    universum = super.callPackage ./pkgs/universum.nix { };
    serokell-util = super.callPackage ./pkgs/serokell-util.nix { };
    acid-state = super.callPackage ./pkgs/acid-state.nix { };
    log-warper = super.callPackage ./pkgs/log-warper.nix { };
    ed25519 = super.callPackage ./pkgs/ed25519.nix { };
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
    servant-server = super.servant-server_0_10;
    servant-swagger = super.servant-swagger_1_1_2_1;
    servant-docs = super.servant-docs_0_10;

    memory = super.memory_0_14_5;
    cryptonite = super.cryptonite_0_23;
    foundation = super.foundation_0_0_8;

    # sl-explorer fixes
    map-syntax = dontCheck super.map-syntax;
    snap = dontCheck super.snap;

    socket-io = super.callCabal2nix "socket-io" "${socket-io-src}/socket-io" {};
    engine-io = super.callCabal2nix "engine-io" "${socket-io-src}/engine-io" {};
    engine-io-wai = super.callCabal2nix "engine-io-wai" "${socket-io-src}/engine-io-wai" {};

    # TODO: https://github.com/NixOS/cabal2nix/issues/261
    cardano-sl-core = prodMode (super.callCabal2nix "cardano-sl-core" "${cardano-sl-src}/core" {});
    cardano-sl-db = super.callCabal2nix "cardano-sl-db" "${cardano-sl-src}/db" {};
    cardano-sl-infra = prodMode (super.callCabal2nix "cardano-sl-infra" "${cardano-sl-src}/infra" {});
    cardano-sl-lrc = super.callCabal2nix "cardano-sl-lrc" "${cardano-sl-src}/lrc" {};
    cardano-sl-update = super.callCabal2nix "cardano-sl-update" "${cardano-sl-src}/update" {};
    cardano-sl-explorer = prodMode (super.callPackage ./pkgs/cardano-sl-explorer.nix { });

    cardano-sl = overrideCabal (super.callCabal2nix "cardano-sl" cardano-sl-src {}) (drv: {
      doHaddock = false;
      patchPhase = ''
       export CSL_SYSTEM_TAG=linux64
      '';
      # production full nodes shouldn't use wallet as it means different constants
      configureFlags = [ "-f-asserts" "-f-dev-mode" "-fwith-explorer"];
    });
    cardano-sl-static = justStaticExecutables self.cardano-sl;
    cardano-report-server-static = justStaticExecutables self.cardano-report-server;
    cardano-sl-explorer-static = justStaticExecutables self.cardano-sl-explorer;

    #mkDerivation = args: super.mkDerivation (args // {
    #enableLibraryProfiling = false;
    #});
  };
}
