{ mkDerivation, async, attoparsec, base, binary, bytestring
, containers, criterion, data-default, deepseq, ekg, ekg-core
, exceptions, fetchgit, formatting, hashable, hspec, kademlia, lens
, log-warper, mmorph, monad-control, mtl, mwc-random, network
, network-transport, network-transport-inmemory
, network-transport-tcp, QuickCheck, quickcheck-instances, random
, semigroups, serokell-util, statistics, stdenv, stm, text
, text-format, time, time-units, transformers, transformers-base
, universum, unordered-containers, vector
}:
mkDerivation {
  pname = "node-sketch";
  version = "0.1.2.0";
  src = fetchgit {
    url = "https://github.com/serokell/time-warp-nt.git";
    sha256 = "1q07zzz3zra2ph5ina3zc5xmnbm3xv9wkwalyd9m4jdzdjdrcczx";
    rev = "c1cc0aa01bbf3ddb0bc2638911afd67cd65e041a";
  };
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    async attoparsec base binary bytestring containers data-default
    deepseq ekg ekg-core exceptions formatting hashable kademlia lens
    log-warper mmorph monad-control mtl mwc-random network
    network-transport network-transport-tcp random semigroups
    serokell-util statistics stm text text-format time time-units
    transformers transformers-base universum unordered-containers
    vector
  ];
  executableHaskellDepends = [
    async base binary bytestring containers criterion mwc-random
    network-transport network-transport-tcp random statistics stm time
    time-units vector
  ];
  testHaskellDepends = [
    base binary bytestring containers hspec lens mtl network-transport
    network-transport-inmemory network-transport-tcp QuickCheck
    quickcheck-instances random serokell-util stm time-units
  ];
  doCheck = false;
  license = stdenv.lib.licenses.mit;
}
