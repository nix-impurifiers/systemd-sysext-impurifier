# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "systemd-sysext-impurifier";
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
  };
  makeExtension =
    {
      applications,
      name ? "nix-impurifiers",
      osRelease ? {
        ID = "_any";
      },
    }:
    assert lib.assertMsg (builtins.match "[a-z0-9][a-z0-9_.-]+" name != null) "invalid extension name";
    assert lib.assertMsg (
      osRelease ? ID
      && lib.all (
        k:
        lib.elem k [
          "ID"
          "VERSION_ID"
          "SYSEXT_LEVEL"
          "ARCHITECTURE"
        ]
      ) (builtins.attrNames osRelease)
    ) "invalid extension compatibility fields";
    assert lib.assertMsg (lib.all (
      v: builtins.isString v && builtins.match "[A-Za-z0-9_.-]+" v != null
    ) (builtins.attrValues osRelease)) "invalid extension compatibility value";
    let
      payloads = map (
        args:
        assert lib.assertMsg
          (
            (args.configFiles or { }) == { }
            && (args.openrc or null) == null
            && (args.runit or null) == null
            && (args.hostBackend or "systemd") == "systemd"
            && (args.mode or "full") == "full"
          )
          "sysext supports /usr assets and systemd; /etc configuration requires a separate native configuration mechanism";
        core.makePayload args
      ) applications;
    in
    pkgs.runCommand "${name}-sysext"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.squashfsTools
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        python3 ${./merge.py} root ${core.makeRuntimeTree { }} ${lib.concatStringsSep " " (map toString payloads)}
        test ! -e root/usr/lib/systemd-sysext-impurifier/boot.py
        install -Dm644 ${./boot.py} root/usr/lib/systemd-sysext-impurifier/boot.py
        test ! -e root/usr/lib/extension-release.d
        test ! -e root/usr/lib/systemd/system/systemd-sysext-impurifier.service
        mkdir -p root/usr/lib/extension-release.d "$out"
        cat > root/usr/lib/extension-release.d/extension-release.${name} <<'RELEASE'
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}=${v}") osRelease)}
        EXTENSION_RELOAD_MANAGER=1
        RELEASE
        ${lib.concatMapStringsSep "\n" (
          args:
          lib.optionalString ((args.systemd or null) != null) ''
            mkdir -p root/usr/lib/systemd/system/${args.name or args.pkg.pname}.service.d
            cat > root/usr/lib/systemd/system/${args.name or args.pkg.pname}.service.d/impurifier-activation.conf <<'DROPIN'
            [Unit]
            After=systemd-sysext-impurifier.service
            DROPIN
          ''
        ) applications}
        env -u SOURCE_DATE_EPOCH mksquashfs root "$out/${name}.raw" -noappend -all-root -all-time 1 -mkfs-time 1 -no-progress -processors 1
      '';
  bootUnit = pkgs.writeText "systemd-sysext-impurifier.service" ''
    [Unit]
    Description=Reconcile Nix intent from native system extensions
    Requires=systemd-sysext.service
    After=systemd-sysext.service
    Before=multi-user.target
    [Service]
    Type=oneshot
    ExecStart=/usr/bin/python3 /usr/lib/systemd-sysext-impurifier/boot.py
    RemainAfterExit=yes
    [Install]
    WantedBy=multi-user.target
  '';
  adapter = pkgs.writeShellApplication {
    name = "systemd-sysext-impurifier";
    runtimeInputs = [
      pkgs.systemd
      core.engine
    ];
    derivationArgs.postInstall = ''
      install -Dm644 ${bootUnit} $out/share/systemd/system/systemd-sysext-impurifier.service
    '';
    text = ''
      case "''${1:-}" in
        merge|refresh|unmerge)
          test "$#" = 1 || { echo 'root/options are not supported by the host adapter' >&2; exit 1; }
          native=0
          systemd-sysext "$1" || native=$?
          activation=0
          nix-profile-engine reconcile || activation=$?
          if [ "$native" -ne 0 ]; then exit "$native"; fi
          exit "$activation"
          ;;
        status|list) exec systemd-sysext "$@" ;;
        *) echo 'usage: systemd-sysext-impurifier {merge|refresh|unmerge|status|list}' >&2; exit 2 ;;
      esac
    '';
  };
in
core // { inherit makeExtension adapter bootUnit; }
