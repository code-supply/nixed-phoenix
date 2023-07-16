{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
    phoenix-utils.url = "/home/andrew/workspace/phoenix-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    phoenix-utils,
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
        pname = "my_new_project";
        version = "0.0.1";
        src = ./.;
        webApp = phoenix-utils.lib.buildPhoenixApp {
          inherit pkgs pname src version;
          mixDepsSha256 = "sha256-dKMSPLv18xyAPdjCkN/iVQCZ8h1RYKSdjuIILMj+hzY=";
          tailwindPath = "_build/tailwind-${systemAbbrs.${system}}";
          esbuildPath = "_build/esbuild-${systemAbbrs.${system}}";
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
          lib = {
            inherit buildPhoenixApp;
          };
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
