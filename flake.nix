# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    foundry.url = "github:shazow/foundry.nix/stable"; # Use stable branch for permanent releases
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
      foundry,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ foundry.overlay ];
        };
      in
      {

        devShell =
          with pkgs;
          mkShell {
            buildInputs = [
              # From the foundry overlay
              # Note: Can also be referenced without overlaying as: foundry.defaultPackage.${system}
              foundry-bin

              # ... any other dependencies we need
              solc
            ];

            # Decorative prompt override so we know when we're in a dev shell
            shellHook = ''
              export PS1="[dev] $PS1"
            '';
          };
      }
    );
}
