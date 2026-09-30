# ghakexec

Can a GitHub-hosted runner kexec into a different kernel?
Can you then run your own operating system on the runner?

Measured 2026-09-30 on `ubuntu-latest` (image `20260920.314.1`).

## Result

**The kexec call works. The job does not survive it.**

A GitHub-hosted runner is an ordinary Azure Hyper-V VM. Secure Boot is off, so
kernel lockdown is off, and root may load and boot another kernel. `kexec -l`
returned 0.

`kexec -e` then switches the kernel. The runner agent dies with the old kernel.
The job can never report again.

## Measurements

| probe | value |
| --- | --- |
| kernel | `6.17.0-1022-azure`, x86_64 |
| distro | Ubuntu 24.04.5 |
| virt | `systemd-detect-virt` = `microsoft` (Hyper-V), EFI firmware |
| region | Azure `centralus` |
| Secure Boot | disabled |
| lockdown | `[none] integrity confidentiality` (not active) |
| `kernel.kexec_load_disabled` | `0` |
| kernel config | `CONFIG_KEXEC=y`, `CONFIG_KEXEC_FILE=y`, `CONFIG_KEXEC_SIG=y`, `CONFIG_KEXEC_SIG_FORCE` unset |
| `/dev/kvm` | present |
| privilege | user `runner` (uid 1001), passwordless `sudo` to root |
| `kexec -l` of the running kernel | exit 0 |

Secure Boot is off, so `CONFIG_KEXEC_SIG` enforces nothing. An unsigned custom
kernel, such as a NixOS `bzImage`, will load.

## What `kexec -e` does to the job

The kernel switch replaces the kernel and every process. The runner agent is one
of them. The GitHub side then sees a silent runner:

- the job stays `in_progress`;
- no error appears;
- a cancel request cannot reach the runner;
- GitHub reaps the job on its timeout.

So there are no artifacts, no status and no later steps. The VM is fine. The job
lifecycle is what breaks.

## Can our own image contain the GitHub runner image?

Partly. Not in a way that keeps a job alive.

The runner's OS disk is GitHub's Ubuntu image. You do not build it, so you cannot
replace its base OS. GitHub-hosted *custom images* (larger runners, Team or
Enterprise) build on top of the official Ubuntu runner image. The base OS stays
Ubuntu. You can bake in Nix, but you cannot boot NixOS as the runner OS this way.

You can make your own OS be the runner only on a **self-hosted** runner, where you
own the VM. There kexec works, and the runner service restarts after the boot.

You cannot carry the *same job* across a kernel switch on any image. A job belongs
to one runner process. The switch kills that process. A new agent is a new runner
and takes new jobs.

## Practical routes to NixOS on a runner

1. **Nested guest, with KVM.** `/dev/kvm` is present on x86 runners. A NixOS QEMU
   guest runs near-native, and the GHA job stays alive with normal status and
   artifacts. This route needs no tricks.
2. **kexec a self-contained workload.** kexec into a RAM-backed NixOS, do the work,
   and report out-of-band (HTTP, or a git push). The job ends as a lost run.
3. **Self-hosted NixOS runner.** You own the VM, so you own the kernel.
   `nixos-anywhere` and the `nixos-images` kexec installer boot NixOS on a running
   Linux host this way.

## It works: the kexec'd NixOS completes a real run

On 2026-09-30 a hosted runner kexec'd into an in-memory NixOS, which started the
real GitHub runner agent, picked up a queued job, and completed it green.

Run: <https://github.com/Lillecarl/ghakexec/actions/runs/36779212908>

The job printed:

```
Linux nixos-kexec 6.18.54 #1-NixOS SMP PREEMPT_DYNAMIC ... x86_64 GNU/Linux
PRETTY_NAME="NixOS 26.11 (Zokor)"
```

How it is built:

- `.github/workflows/kexec-boot.yml` builds `packages.x86_64-linux.kexec` (a
  NixOS netboot image), mints a runner registration token, and kexecs.
- `nix/runner-image.nix` boots NixOS with DHCP and a systemd unit that reads the
  token from the kernel command line and runs `Runner.Listener`.
- `.github/workflows/nixos-run.yml` is queued on `self-hosted, nixos-kexec` and
  runs once that runner comes online.

Two traps cost a run each:

- `kexec_file_load` verifies the kernel signature and rejects an unsigned NixOS
  kernel with `EPERM`. Load with the legacy `kexec_load` syscall
  (`kexec --kexec-syscall`), which does not check signatures.
- A job step runs as the unprivileged `runner` user. The kexec run script must
  call `sudo`, or both syscalls return `EPERM`.

The same job cannot go green: after `kexec -e` the hosted agent is gone, and no
API sets a job conclusion. The kexec-boot run above ends as a cancelled run. The
green run is a separate job that the new NixOS runner takes.

## Reproduce

`.github/workflows/recon.yml` is manual-dispatch only. It reports the environment
and runs `kexec -l` (load only, no reboot). A boolean input enables `kexec -e`.

The self-hosted demonstration is manual-dispatch only too. Dispatch `nixos-run`
first (it queues), then `kexec-boot`. It needs a `GHAKEXEC_PAT` repository secret
with permission to mint a runner registration token.

## Scope

A handful of measurements, on one runner image. The point is the capability, not
volume. kexec of a foreign kernel on a hosted runner sits in GitHub's "nested
virtualization is experimental, at your own risk" territory.
