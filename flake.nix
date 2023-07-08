{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/23.05";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    beamPkgs = pkgs.beam_minimal.packages.erlang_25;
    pname = "my_new_project";
    version = "0.0.1";
    src = ./.;
    elixir = beamPkgs.elixir_1_14;
    erlang = beamPkgs.erlang;
    fetchMixDeps = beamPkgs.fetchMixDeps.override {inherit elixir;};
    mixRelease = beamPkgs.mixRelease.override {inherit elixir erlang fetchMixDeps;};

    mixFodDeps = fetchMixDeps {
      inherit version src;
      pname = "elixir-deps";
      sha256 = "sha256-dKMSPLv18xyAPdjCkN/iVQCZ8h1RYKSdjuIILMj+hzY=";
    };

    webApp = mixRelease {
      inherit src;
      inherit pname;
      inherit version;
      inherit mixFodDeps;
    };
  in {
    packages.x86_64-linux.default = webApp;
  };
}
