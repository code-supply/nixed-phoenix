{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    with flake-utils.lib; let
      systemAbbrs = {
        ${system.aarch64-darwin} = "macos-arm64";
        ${system.x86_64-linux} = "linux-x64";
      };
    in
      eachSystem [
        system.aarch64-darwin
        system.x86_64-linux
      ] (system: let
        pkgs = nixpkgs.legacyPackages.${system};
        beamPkgs = with pkgs.beam_minimal;
          packagesWith (interpreters.erlangR25.override {
            configureFlags = [
              "--without-debugger"
              "--without-et"
              "--without-megaco"
              "--without-observer"
              "--without-termcap"
              "--without-wx"
            ];
            installTargets = ["install"];
          });
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
          inherit src pname version mixFodDeps;

          postBuild = ''
            install ${pkgs.tailwindcss}/bin/tailwindcss _build/tailwind-${systemAbbrs.${system}}
            install ${pkgs.esbuild}/bin/esbuild _build/esbuild-${systemAbbrs.${system}}
            cp -a /build/deps ./
            mix assets.deploy
          '';
        };

        dockerImage =
          pkgs.dockerTools.buildImage
          {
            name = "mygreatdocker/image";
            tag = version;
            config = {
              Cmd = ["${webApp}/bin/${pname}" "start"];
              Env = ["PATH=/bin:$PATH" "LC_ALL=C.UTF-8"];
            };
            copyToRoot = pkgs.buildEnv {
              name = "image-root";
              paths = with pkgs; [
                bash
                coreutils
                gnugrep
                gnused
              ];
              pathsToLink = ["/bin"];
            };
          };
      in {
        packages = {
          default = webApp;
          inherit dockerImage;
        };
        devShells.default = with pkgs;
          mkShell {
            packages = [
              elixir
              (elixir_ls.override {inherit elixir;})
              erlang
              esbuild
              tailwindcss
            ];
          };
      });
}
