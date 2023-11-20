final: prev: {
  jdtls = prev.callPackage ../packages/jdtls {
    inherit (prev) stdenv fetchzip lib pkgs;
  };
}
