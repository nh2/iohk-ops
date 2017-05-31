{ mkDerivation, base, bytestring, cryptonite, cryptonite-openssl
, deepseq, fetchgit, hashable, memory, stdenv, tasty
, tasty-quickcheck
}:
mkDerivation {
  pname = "cardano-crypto";
  version = "1.0.0";
  src = fetchgit {
    url = "https://github.com/input-output-hk/cardano-crypto";
    sha256 = "1nxm0vlg9w841cc4gyy87jk4hvc3iimpjv2a9q6d99ri7v4ynnb4";
    rev = "96adbd5aa9a906859deddf170f8762a9ed85c0c9";
  };
  libraryHaskellDepends = [
    base bytestring cryptonite cryptonite-openssl deepseq hashable
    memory
  ];
  testHaskellDepends = [
    base bytestring cryptonite memory tasty tasty-quickcheck
  ];
  doCheck = false;
  homepage = "https://github.com/input-output-hk/cardano-crypto#readme";
  description = "Cryptography primitives for cardano";
  license = stdenv.lib.licenses.mit;
}
