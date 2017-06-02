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
                   (githubSrc "input-output-hk/stack2nix" "616002fa861e809b5c955302af33f0a249257ddb" "0hzw1r8kdsi08lsbd10y7z5945mdf6l57lcfjv00n9fzw26np704") {});
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

  s2n-cardano-sl          = import ./pkgs/cardano-sl.nix {};
  s2n-cardano-sl-explorer = import ./pkgs/cardano-sl-explorer.nix {};

in compiler.override {
  overrides = self: super: {
    inherit cabal2nix stack2nix;

    # TODO: https://github.com/NixOS/cabal2nix/issues/261
    cardano-sl-core     = prodMode s2n-cardano-sl.cardano-sl-core;
    cardano-sl-db       =          s2n-cardano-sl.cardano-sl-db;
    cardano-sl-infra    = prodMode s2n-cardano-sl.cardano-sl-infra;
    cardano-sl-lrc      =          s2n-cardano-sl.cardano-sl-lrc;
    cardano-sl-update   =          s2n-cardano-sl.cardano-sl-update;

    cardano-sl-explorer = prodMode s2n-cardano-sl-explorer;

    ## TODO: replace with:     (callStack2nix self "cardano-sl" cardano-sl-src {})
    cardano-sl     = overrideCabal s2n-cardano-sl.cardano-sl (drv: {
      doHaddock = false;
      patchPhase = ''
       export CSL_SYSTEM_TAG=linux64
      '';
      # production full nodes shouldn't use wallet as it means different constants
      configureFlags = [ "-f-asserts" "-f-dev-mode" "-fwith-explorer --ghc-option=-fno-specialise --verbose"];
    });
    cardano-sl-static            = justStaticExecutables self.cardano-sl;

    cardano-report-server-static = justStaticExecutables stack2nix-pkgs.cardano-report-server;
    cardano-sl-explorer-static   = justStaticExecutables self.cardano-sl-explorer;

    #mkDerivation = args: super.mkDerivation (args // {
    #enableLibraryProfiling = false;
    #});
  };
}
