{
  description = "All the software needed to develop and deploy hobby hoster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };
  in {
    defaultPackage.${system} = with pkgs; stdenv.mkDerivation {
      name = "hobby-hoster";
      src = ./.;
      buildInputs = [
        terraform
        terragrunt
        bashInteractive
        openssh
        jq
        curl
        git
        python3
        python3Packages.boto3
        python3Packages.click
        python3Packages.paramiko
        go
        nmap # for debugging
      ];
    };
  };
}