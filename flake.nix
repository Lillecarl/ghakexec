{
  description = "kexec a GitHub-hosted runner into in-memory NixOS running the GitHub runner agent";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      cfg = (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./nix/runner-image.nix ];
      }).config;
    in
    {
      packages.${system} = {
        kexec = pkgs.linkFarm "ghakexec-kexec-${system}" [
          {
            name = "bzImage";
            path = "${cfg.system.build.kernel}/${cfg.system.boot.loader.kernelFile}";
          }
          {
            name = "initrd.gz";
            path = "${cfg.system.build.netbootRamdisk}/initrd";
          }
          {
            name = "run";
            path = cfg.system.build.ghakexecKexecRun;
          }
        ];

        tarball = pkgs.runCommand "ghakexec-kexec-tarball" { } ''
          mkdir -p $out kexec
          cp ${cfg.system.build.kernel}/${cfg.system.boot.loader.kernelFile} kexec/bzImage
          cp ${cfg.system.build.netbootRamdisk}/initrd kexec/initrd.gz
          cp ${cfg.system.build.ghakexecKexecRun} kexec/run
          chmod +x kexec/run
          tar -C kexec -czf $out/ghakexec-kexec.tar.gz .
        '';
      };
    };
}
