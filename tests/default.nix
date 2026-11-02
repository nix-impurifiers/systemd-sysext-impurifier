# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  tool =
    version:
    pkgs.runCommand "sysext-tool-${version}"
      {
        pname = "sysext-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/sysext-tool
        chmod +x $out/bin/sysext-tool
      '';
  daemon =
    version:
    pkgs.runCommand "sysext-daemon-${version}"
      {
        pname = "sysext-daemon";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/sysext-daemon <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/sysext-daemon/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/sysext-daemon
      '';
  image =
    offline: version:
    impurifier.makeExtension {
      applications = [
        {
          pkg = tool version;
          inherit offline;
        }
        {
          pkg = daemon version;
          inherit offline;
          users.sysext-daemon = { };
          directories."/var/lib/sysext-daemon" = {
            owner = "sysext-daemon:sysext-daemon";
            mode = "0750";
          };
          lifecycle.onInstall = "echo initialized > /var/lib/sysext-daemon/initialized";
          lifecycle.onUpgrade = "test ! -e /run/fail-sysext; echo ${version} > /var/lib/sysext-daemon/migrated";
          systemd.unit = pkgs.writeText "sysext-daemon.service" ''
            [Service]
            Type=exec
            User=sysext-daemon
            ExecStart=/opt/nix/profile/bin/sysext-daemon
            [Install]
            WantedBy=multi-user.target
          '';
        }
      ];
    };
  example = impurifier.makeExtension {
    applications = [
      {
        pkg = pkgs.hello;
        offline = true;
      }
    ];
  };
  closure = pkgs.closureInfo { rootPaths = [ example ]; };
  invalidConfig = builtins.tryEval (
    (impurifier.makeExtension {
      applications = [
        {
          pkg = pkgs.hello;
          configFiles."/etc/unsupported" = pkgs.writeText "config" "data";
        }
      ];
    }).drvPath
  );
in
assert !invalidConfig.success;
{
  contract =
    pkgs.runCommand "sysext-contract"
      {
        nativeBuildInputs = [
          pkgs.squashfsTools
          pkgs.python3
        ];
      }
      ''
        unsquashfs -cat ${example}/nix-impurifiers.raw usr/lib/extension-release.d/extension-release.nix-impurifiers | grep '^ID=_any$'
        grep '^After=systemd-sysext.service$' ${impurifier.bootUnit}
        test "$(wc -l < ${closure}/store-paths)" = 1
        mkdir -p first/usr/share second/usr/share outside/etc
        echo first > first/usr/share/collision
        echo second > second/usr/share/collision
        if python3 ${../nix/merge.py} merged first second; then exit 1; fi
        if python3 ${../nix/merge.py} unsupported outside; then exit 1; fi
        touch $out
      '';
  unit = impurifier.unit;
  vm = pkgs.testers.runNixOSTest {
    name = "systemd-sysext-impurifier";
    requiredFeatures = {
      kvm = false;
      devnet = false;
    };
    nodes.machine = { lib, ... }: {
      virtualisation.memorySize = 2048;
      virtualisation.useNixStoreImage = true;
      virtualisation.writableStore = true;
      virtualisation.writableStoreUseTmpfs = false;
      virtualisation.diskSize = 3072;
      virtualisation.qemu.package = lib.mkForce pkgs.qemu;
      virtualisation.qemu.forceAccel = false;
      boot.kernelModules = [
        "squashfs"
        "overlay"
        "loop"
      ];
      environment.systemPackages = [
        impurifier.adapter
        pkgs.nix
        pkgs.python3
      ];
      systemd.additionalUpstreamSystemUnits = [ "systemd-sysext.service" ];
      systemd.tmpfiles.rules = [
        "d /usr/bin 0755 root root -"
        "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
        "L+ /usr/bin/systemctl - - - - ${pkgs.systemd}/bin/systemctl"
        "L+ /usr/bin/systemd-sysusers - - - - ${pkgs.systemd}/bin/systemd-sysusers"
        "L+ /usr/bin/systemd-tmpfiles - - - - ${pkgs.systemd}/bin/systemd-tmpfiles"
        "L+ /usr/bin/nix-store - - - - ${pkgs.nix}/bin/nix-store"
      ];
      system.activationScripts.nativeUnitState = {
        deps = [ "etc" ];
        text = ''
          if [ -d /var/lib/impurifier-vm/systemd-system ]; then
            rm -f /etc/systemd/system
            ln -s /var/lib/impurifier-vm/systemd-system /etc/systemd/system
          fi
        '';
      };
      nix.settings.substituters = lib.mkForce [ ];
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.succeed("systemctl stop dhcpcd; ip link set eth0 down; mkdir -p /var/lib/extensions")
      machine.succeed("python3 ${./mutable-units.py}; install -m644 ${impurifier.bootUnit} /etc/systemd/system/systemd-sysext-impurifier.service; systemctl daemon-reload; ${impurifier.engine}/bin/nix-profile-engine reconcile")
      machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
      def publish(source):
          machine.succeed("cp " + source + "/nix-impurifiers.raw /var/lib/extensions/.incoming; chmod 644 /var/lib/extensions/.incoming; mv /var/lib/extensions/.incoming /var/lib/extensions/nix-impurifiers.raw")
      with subtest("foreign-root mutation is rejected without activation"):
          before = machine.succeed("readlink /opt/nix/profile").strip()
          code, output = machine.execute("systemd-sysext-impurifier refresh --root /tmp/foreign 2>&1")
          assert code != 0 and "root/options" in output, output
          assert machine.succeed("readlink /opt/nix/profile").strip() == before
      with subtest("native merge fails net realization without replacing the profile"):
          before = machine.succeed("readlink /opt/nix/profile").strip()
          publish("${image false "1"}")
          code, output = machine.execute("systemd-sysext-impurifier refresh 2>&1")
          assert code != 0 and "nix-profile-engine:" in output, output
          assert machine.succeed("readlink /opt/nix/profile").strip() == before
      with subtest("native offline image activates accounts, lifecycle and service"):
          publish("${image true "1"}")
          machine.succeed("systemd-sysext-impurifier refresh")
          machine.succeed("/opt/nix/profile/bin/sysext-tool | grep '^1$'")
          machine.wait_for_unit("sysext-daemon.service")
          machine.succeed("systemctl enable systemd-sysext.service systemd-sysext-impurifier.service")
          machine.succeed("grep initialized /var/lib/sysext-daemon/initialized; test $(stat -c %U /var/lib/sysext-daemon) = sysext-daemon")
      with subtest("failed migration is retried after native image replacement"):
          machine.succeed("touch /run/fail-sysext")
          publish("${image true "2"}")
          machine.fail("systemd-sysext-impurifier refresh")
          machine.succeed("rm /run/fail-sysext; systemd-sysext-impurifier refresh")
          machine.wait_until_succeeds("grep '^2$' /var/lib/sysext-daemon/version")
          machine.succeed("grep '^2$' /var/lib/sysext-daemon/migrated")
      with subtest("administrator stopped service remains stopped on downgrade"):
          machine.succeed("systemctl disable --now sysext-daemon.service")
          publish("${image true "1"}")
          machine.succeed("systemd-sysext-impurifier refresh")
          machine.fail("systemctl is-active --quiet sysext-daemon.service")
          machine.fail("systemctl is-enabled --quiet sysext-daemon.service")
      with subtest("real reboot reloads the native image after garbage collection"):
          machine.succeed("nix-store --gc; /opt/nix/profile/bin/sysext-tool | grep '^1$'")
          machine.shutdown()
          machine.start()
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("systemd-sysext-impurifier.service")
          machine.succeed("/opt/nix/profile/bin/sysext-tool | grep '^1$'")
          machine.fail("systemctl is-active --quiet sysext-daemon.service")
      with subtest("enabled bundled service starts after real boot reconciliation"):
          machine.succeed("systemctl enable --now sysext-daemon.service")
          machine.shutdown()
          machine.start()
          machine.wait_for_unit("systemd-sysext-impurifier.service")
          machine.wait_for_unit("sysext-daemon.service")
      with subtest("native unmerge removes intent and stops running service"):
          machine.succeed("systemctl enable --now sysext-daemon.service")
          machine.succeed("rm /var/lib/extensions/nix-impurifiers.raw; systemd-sysext-impurifier refresh")
          machine.fail("test -e /opt/nix/profile/bin/sysext-tool")
          machine.fail("systemctl is-active --quiet sysext-daemon.service")
          machine.succeed("${impurifier.engine}/bin/nix-profile-engine prune --keep 0; nix-store --gc")
    '';
  };
}
