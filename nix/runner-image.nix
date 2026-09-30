{ config, lib, pkgs, modulesPath, ... }:

let
  runnerName = "nixos-kexec";
in
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
  ];

  networking.hostName = runnerName;
  networking.networkmanager.enable = lib.mkForce false;
  networking.useNetworkd = true;
  networking.useDHCP = lib.mkForce true;
  networking.firewall.enable = false;

  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/github-runner 0700 root root -"
  ];

  systemd.services.github-runner = {
    description = "GitHub Actions self-hosted runner on in-memory NixOS";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = with pkgs; [
      bashInteractive
      coreutils
      git
      gnutar
      gzip
      which
      findutils
      curl
    ];
    environment = {
      HOME = "/var/lib/github-runner";
      RUNNER_ROOT = "/var/lib/github-runner";
      DOTNET_CLI_TELEMETRY_OPTOUT = "1";
      DOTNET_NOLOGO = "1";
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/var/lib/github-runner";
      Restart = "on-failure";
      RestartSec = 15;
      ExecStartPre = pkgs.writeShellScript "github-runner-configure" ''
        set -euo pipefail
        mkdir -p /var/lib/github-runner
        cmdline=$(cat /proc/cmdline)
        token=$(printf '%s' "$cmdline" | sed -n 's/.*ghakexec\.token=\([^ ]*\).*/\1/p')
        url=$(printf '%s' "$cmdline" | sed -n 's/.*ghakexec\.url=\([^ ]*\).*/\1/p')
        name=$(printf '%s' "$cmdline" | sed -n 's/.*ghakexec\.name=\([^ ]*\).*/\1/p')
        test -n "$token"
        test -n "$url"
        test -n "$name"
        exec ${pkgs.github-runner}/bin/Runner.Listener configure \
          --unattended --ephemeral --replace --disableupdate \
          --url "$url" --token "$token" --name "$name" \
          --labels ${runnerName} --work /var/lib/github-runner/_work
      '';
      ExecStart = "${pkgs.github-runner}/bin/Runner.Listener run --startuptype service";
    };
  };

  system.stateVersion = config.system.nixos.release;

  system.build.ghakexecKexecRun = pkgs.writeShellScript "ghakexec-kexec-run" ''
    set -eux
    dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    : "''${GHAKEXEC_TOKEN:?set GHAKEXEC_TOKEN}"
    : "''${GHAKEXEC_URL:?set GHAKEXEC_URL}"
    name="''${GHAKEXEC_NAME:-${runnerName}}"
    command_line="init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams} ghakexec.token=$GHAKEXEC_TOKEN ghakexec.url=$GHAKEXEC_URL ghakexec.name=$name"
    command -v kexec >/dev/null || { echo "kexec not found" >&2; exit 1; }
    kexec --load "$dir/bzImage" --initrd="$dir/initrd.gz" --no-checks \
      --command-line "$command_line"
    kexec -e
  '';
}
