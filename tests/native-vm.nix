# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  image =
    version:
    impurifier.makeNativeExtension {
      name = "native-proof";
      payload = pkgs.runCommand "native-sysext-${version}" { } ''
        mkdir -p $out/usr/libexec/native-proof $out/usr/share
        cp ${pkgs.pkgsStatic.busybox}/bin/busybox $out/usr/libexec/native-proof/busybox
        echo ${version} > $out/usr/share/native-proof-version
      '';
    };
in
pkgs.testers.runNixOSTest {
  name = "sysext-native-payload";
  requiredFeatures.kvm = false;
  requiredFeatures.devnet = false;
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    boot.supportedFilesystems = [
      "squashfs"
      "overlay"
    ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /srv/native/usr /srv/native/etc /srv/native/var/lib/extensions; cp /etc/os-release /srv/native/etc/os-release")
    machine.succeed("cp ${image "1"}/native-proof.raw /srv/native/var/lib/extensions/")
    machine.succeed("systemd-sysext --root=/srv/native merge")
    machine.succeed("chroot /srv/native /usr/libexec/native-proof/busybox echo native-execution | grep native-execution")
    machine.succeed("grep '^1$' /srv/native/usr/share/native-proof-version && test ! -e /srv/native/nix && test ! -e /srv/native/usr/sbin/nix-profile-engine")
    machine.succeed("systemd-sysext --root=/srv/native unmerge; cp ${image "2"}/native-proof.raw /srv/native/var/lib/extensions/")
    machine.succeed("systemd-sysext --root=/srv/native merge; grep '^2$' /srv/native/usr/share/native-proof-version")
    machine.succeed("systemd-sysext --root=/srv/native unmerge")
    machine.succeed("test ! -e /srv/native/usr/libexec/native-proof/busybox && test ! -e /srv/native/usr/share/native-proof-version && test ! -e /srv/native/nix")
  '';
}
