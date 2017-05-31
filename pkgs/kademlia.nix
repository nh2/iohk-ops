{ mkDerivation, base, binary, bytestring, containers, cryptonite
, data-default, errors, extra, fetchgit, HUnit, memory, MonadRandom
, mtl, network, QuickCheck, quickcheck-instances, random
, random-shuffle, stdenv, stm, tasty, tasty-hunit, tasty-quickcheck
, time, transformers, transformers-compat
}:
mkDerivation {
  pname = "kademlia";
  version = "1.1.0.1";
  src = fetchgit {
    url = "https://github.com/serokell/kademlia.git";
    sha256 = "1b596ww8jmk7431fg2w5hnq38cipgss178sbpxyzd4gb10gvx4i4";
    rev = "b4b0a6774368b9bbea96d7a03a1a451b6fc3cfea";
  };
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    base binary bytestring containers cryptonite data-default errors
    extra memory MonadRandom mtl network random random-shuffle stm time
    transformers transformers-compat
  ];
  executableHaskellDepends = [
    base binary bytestring containers data-default extra MonadRandom
    mtl network random random-shuffle transformers transformers-compat
  ];
  testHaskellDepends = [
    base binary bytestring containers data-default errors extra HUnit
    MonadRandom mtl network QuickCheck quickcheck-instances random
    random-shuffle stm tasty tasty-hunit tasty-quickcheck time
    transformers transformers-compat
  ];
  doCheck = false;
  homepage = "https://github.com/serokell/kademlia";
  description = "An implementation of the Kademlia DHT Protocol";
  license = stdenv.lib.licenses.bsd3;
}
