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

    tailwindBinary = pkgs.fetchurl {
      url = "https://github.com/tailwindlabs/tailwindcss/releases/download/v3.2.7/tailwindcss-linux-x64";
      sha256 = "sha256-NeT6JTr03atzSQt0Q7fQjwxmSo2LO4eOrcu1Sn4GR/g=";
    };

    esbuildBinary = pkgs.fetchzip {
      url = "https://registry.npmjs.org/@esbuild/linux-x64/-/linux-x64-0.17.11.tgz";
      sha256 = "sha256-AUHohCkJqS/WdnT8TZ+h+/JFUs/s1hnYExz9Ebg5HB8=";
    };

    mixFodDeps = fetchMixDeps {
      inherit version src;
      pname = "elixir-deps";
      sha256 = "sha256-dKMSPLv18xyAPdjCkN/iVQCZ8h1RYKSdjuIILMj+hzY=";
    };

    webApp = mixRelease {
      inherit src pname version mixFodDeps;

      postBuild = ''
        install ${tailwindBinary} _build/tailwind-linux-x64
        install ${esbuildBinary}/bin/esbuild _build/esbuild-linux-x64
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
    packages.x86_64-linux = {
      default = webApp;
      inherit dockerImage;
    };
    devShells.${system}.default = with pkgs;
      mkShell {
        packages = [
          elixir
          erlang
          (elixir_ls.override {inherit elixir;})
        ];
      };
  };
}
