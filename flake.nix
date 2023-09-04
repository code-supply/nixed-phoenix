{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      pname = "my_new_project";
      version =
        if self ? rev
        then self.rev
        else "dirty";
      src = ./.;
      beamPackages = with pkgs.beam_minimal; packagesWith interpreters.erlangR25;
      erlang = beamPackages.erlang;
      elixir = beamPackages.elixir_1_14;
      fetchMixDeps = beamPackages.fetchMixDeps.override { inherit elixir; };
      mixRelease = beamPackages.mixRelease.override { inherit elixir erlang fetchMixDeps; };
      mixNixDeps = (import ./deps.nix) {
        inherit beamPackages;
        lib = pkgs.lib;
        overrides =
          let
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

      webApp = mixRelease {
        inherit pname src version system mixNixDeps;

        stripDebug = true;

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
              Cmd = [ "${webApp}/bin/server" ];
              Env = [ "LC_ALL=C.UTF-8" ];
            };
            copyToRoot = pkgs.buildEnv {
              name = "image-root";
              paths = [ pkgs.busybox ];
              pathsToLink = [ "/bin" ];
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
      ciRunTests = with pkgs;
        writeShellScriptBin "ci-run-tests" ''
          mkdir deps
          mkdir -p _build/test/lib
          while read -r -d ':' lib
          do
            for dir in "$lib/"/*
            do
              dest="$(basename "$dir" | cut -d '-' -f1)"
              build_dir="_build/test/lib/$dest"
              ln -sfv "$dir" "$build_dir"
              ln -sfv "$dir" "deps/$dest"
            done
          done <<< "$ERL_LIBS:"
          MIX_ENV=test mix do deps.loadpaths --no-deps-check, test
        '';
      shellHook = ''
        export PGHOST="$(git rev-parse --show-toplevel)/.postgres"
      '';
    in
    {
      formatter = {
        ${system} = pkgs.nixpkgs-fmt;
      };
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
              elixir
              (elixir_ls.override { inherit elixir; })
              erlang
              inotify-tools
              mix2nix
              nixpkgs-fmt
              postgresql_15
              postgresStart
              postgresStop
            ];
          };
        ci = with pkgs;
          mkShell {
            inherit shellHook;
            packages = [
              beamPackages.hex
              ciRunTests
              elixir
              postgresql_15
              postgresStart
            ] ++ builtins.attrValues mixNixDeps;
          };
      };
    };
}
