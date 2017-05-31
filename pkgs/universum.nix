{ mkDerivation, base, bytestring, containers, deepseq, exceptions
, fetchgit, ghc-prim, hashable, microlens, microlens-mtl, mtl, safe
, stdenv, stm, text, text-format, transformers, type-operators
, unordered-containers, utf8-string, vector
}:
mkDerivation {
  pname = "universum";
  version = "0.4.2";
  src = fetchgit {
    url = "https://github.com/serokell/universum";
    sha256 = "12mdpdqfag5wgcfda0xmf32srn4kx704arq6xc2z1rx1yqr95lja";
    rev = "7fc58d5756ff44beac914b7a597d9cca36235ea3";
  };
  libraryHaskellDepends = [
    base bytestring containers deepseq exceptions ghc-prim hashable
    microlens microlens-mtl mtl safe stm text text-format transformers
    type-operators unordered-containers utf8-string vector
  ];
  doCheck = false;
  homepage = "https://github.com/serokell/universum";
  description = "Custom prelude used in Serokell";
  license = stdenv.lib.licenses.mit;
}
