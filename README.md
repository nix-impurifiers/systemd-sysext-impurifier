# systemd-sysext-impurifier

Build native SquashFS system extension images carrying Nix applications, package
intent, systemd units and offline closure caches. Native `systemd-sysext` owns
merging `/usr`; the [shared engine](https://github.com/nix-impurifiers/impurifier)
owns GC roots and atomic `/opt/nix/profile` generations. Original code is MIT.

```nix
let
  impurifier = inputs.systemd-sysext-impurifier.lib.systemd-sysext-impurifier {inherit pkgs;};
in impurifier.makeExtension {
  applications = [
    {pkg=pkgs.hello; offline=true;}
  ];
}
```

The output directory contains the canonical `nix-impurifiers.raw` filename.
Manage one impurifier bundle per host; put all selected applications in that
bundle. Do not install net and offline images alongside each other. The native
extension mechanism merges all installed extensions and cannot solve overlapping
package ownership between separate impurifier bundles.

Nix and Python 3 must already be installed and available through standard host
paths. Install the matching `adapter` output as an administrator tool. A Nix
provider/installer remains deferred. Place the image in `/var/lib/extensions`
using an atomic replacement, never overwrite an image currently loop-mounted:

```sh
sudo install -m644 ./nix-impurifiers.raw /var/lib/extensions/.incoming
sudo mv /var/lib/extensions/.incoming /var/lib/extensions/nix-impurifiers.raw
sudo install -m644 ./adapter/share/systemd/system/systemd-sysext-impurifier.service /etc/systemd/system/systemd-sysext-impurifier.service
sudo systemctl daemon-reload
sudo systemd-sysext-impurifier refresh
sudo systemctl enable systemd-sysext.service systemd-sysext-impurifier.service
```

Create `/var/lib/extensions` first if needed. Preserve the emitted basename;
`name` changes both filename and its matching native extension-release metadata.
The separately installed host boot unit (also exported as `boot-unit`) must
exist before extensions are merged during boot. A unit supplied only inside an
extension is discovered too late for dependable startup ordering. It requires native `systemd-sysext.service` and reconciles before
bundled application units. Native Nix store, state and profile directories must
persist across reboot. Use a helper and images from matching project revisions.

`applications` accepts full shared payload arguments: per-application `offline`,
`files` under `/usr`, users, directories, lifecycle hooks, systemd units, priority
and explicit host library bindings. Application unit drop-ins follow the host reconciliation unit.
Runtime code and application closures share one image transaction. Colliding files are rejected. `/etc` configuration,
OpenRC and runit payloads are rejected: sysext does not expose `/etc` or `/var`
from an image. Users and `/var` directories are prepared through native sysusers
and tmpfiles after the merge. Configure applications separately through the host's
native configuration mechanism.

`osRelease` accepts `ID`, `VERSION_ID`, `SYSEXT_LEVEL` and `ARCHITECTURE`. The
default is `ID=_any`, appropriate for self-contained Nix programs. Native shared
library requirements remain consumer policy; narrow compatibility metadata when
the image depends on host-specific interfaces. Native extension-release checks
remain enabled. Images are locally administered, unsigned artifacts; this does
not configure global trust policy or provide a remote update service.

The adapter exposes native `merge`, `refresh`, `unmerge`, `status` and `list`.
Mutations run native sysext and then reconcile, preserving either failure status.
No root override is accepted for activation. Status/list remain read-only.
`unmerge` has its native meaning: unmerge all system extensions. For persistent
removal, remove the selected `.raw` file and run `refresh`. When removing the last
impurifier image, disable its boot unit beforehand. The separately installed
adapter remains available after unmerge to release intent and stop services.

Boot activation queues bundled units whose native systemd state is enabled,
after reconciliation completes. Disabled units remain stopped. Manual refresh
preserves a service an administrator stopped during the current session.

Native image merging precedes application activation. Fetch/composition failure
keeps the old published profile; migration/service failure retains retry intent.
Repair the cause and rerun `refresh`, even if native sysext reports no image
change. Lifecycle hooks must be idempotent. Services stopped/disabled by an
administrator retain those decisions across application updates. Garbage
collection remains an explicit administrator action; prune profile generations
through `nix-profile-engine prune` before collecting old closures.

`nix flake check -L` boots QEMU and uses actual systemd-sysext, loop devices,
SquashFS, overlayfs, Nix, sysusers/tmpfiles and service management. The guest has
a persistent writable Nix store. It checks net failure, offline import from
read-only images, atomic image replacement, lifecycle retry, administrator
intent, real reboot after GC, and native unmerge/removal. The NixOS fixture makes
native unit directories writable while preserving dependency symlinks; this does
not claim arbitrary declarative NixOS service-enablement compatibility.
