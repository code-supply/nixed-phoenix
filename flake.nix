{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
    phoenix-utils.url = "github:code-supply/phoenix-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    phoenix-utils,
  }:
    with flake-utils.lib;
      eachSystem [
        system.aarch64-darwin
        system.x86_64-linux
      ] (system: let
        pkgs = nixpkgs.legacyPackages.${system};
        pname = "my_new_project";
        version = "0.0.1";
        src = ./.;
        webApp = phoenix-utils.lib.buildPhoenixApp {
          inherit pkgs pname src version system;
          mix2NixOutput = import ./deps.nix;
          # mixDepsSha256 = "sha256-WbhOZ7LkyVjIxO+6jOGQmzHZGDwNgrHpnKQbNQ9uGKM=";
        };
        dockerImage =
          pkgs.dockerTools.buildImage
          {
            name = "mygreatdocker/image";
            tag = version;
            config = {
              Cmd = ["${webApp.app}/bin/${pname}" "start"];
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
          default = webApp.app;
          inherit dockerImage;
        };
        devShells.default = with pkgs;
          mkShell {
            inherit shellHook;
            packages = [
              (elixir_ls.override {elixir = webApp.elixir;})
              inotify-tools
              mix2nix
              postgresql_15
              postgresStart
              postgresStop
              webApp.elixir
              webApp.erlang
            ];
          };
        devShells.ci = with pkgs;
          mkShell {
            inherit shellHook;
            packages = [
              postgresql_15
              postgresStart
              webApp.elixir
            ];
          };
      });
}
