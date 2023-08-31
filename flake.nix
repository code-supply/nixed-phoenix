{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    pname = "my_new_project";
    version = self.rev;
    src = ./.;
    beamPackages = with pkgs.beam_minimal; packagesWith interpreters.erlangR25;
    erlang = beamPackages.erlang;
    elixir = beamPackages.elixir_1_14;
    fetchMixDeps = beamPackages.fetchMixDeps.override {inherit elixir;};
    mixRelease = beamPackages.mixRelease.override {inherit elixir erlang fetchMixDeps;};
    webApp = mixRelease {
      inherit pname src version system;

      stripDebug = true;

      mixNixDeps = (import ./deps.nix) {
        inherit beamPackages;
        lib = pkgs.lib;
        overrides = let
          overrideFun = old: {
            postInstall = ''
              cp -v package.json "$out/lib/erlang/lib/${old.name}"
            '';
          };
        in
          _: prev: {
            phoenix = prev.phoenix.overrideAttrs overrideFun;
            phoenix_html = prev.phoenix_html.overrideAttrs overrideFun;
            phoenix_live_view = prev.phoenix_live_view.overrideAttrs overrideFun;
          };
      };

      preBuild = ''
        mkdir ./deps
        cp -a _build/prod/lib/. ./deps/
      '';

      postBuild = ''
        ln -sfv ${pkgs.tailwindcss}/bin/tailwindcss _build/tailwind-linux-x64
        ln -sfv ${pkgs.esbuild}/bin/esbuild _build/esbuild-linux-x64

        mix assets.deploy --no-deps-check
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
    postgresStart = with pkgs;
      writeShellScriptBin "postgres-start" ''
        [[ -d "$PGHOST" ]] || \
          ${postgresql_15}/bin/initdb -D "$PGHOST/db"
        ${postgresql_15}/bin/pg_ctl \
          -D "$PGHOST/db" \
          -l "$PGHOST/log" \
          -o "--unix_socket_directories='$PGHOST'" \
          -o "--listen_addresses=" \
          start
      '';
    postgresStop = with pkgs;
      writeShellScriptBin "postgres-stop" ''
        pg_ctl \
          -D "$PGHOST/db" \
          -l "$PGHOST/log" \
          -o "--unix_socket_directories=$PGHOST" \
          stop
      '';
    shellHook = ''
      export PGHOST="$(git rev-parse --show-toplevel)/.postgres"
    '';
  in {
    packages = {
      ${system} = {
        default = webApp;
        inherit dockerImage;
      };
    };
    devShells.${system} = {
      default = with pkgs;
        mkShell {
          inherit shellHook;
          packages = [
            (elixir_ls.override {inherit elixir;})
            inotify-tools
            mix2nix
            postgresql_15
            postgresStart
            postgresStop
            elixir
            erlang
          ];
        };
      ci = with pkgs;
        mkShell {
          inherit shellHook;
          packages = [
            postgresql_15
            postgresStart
            elixir
          ];
        };
    };
  };
}
