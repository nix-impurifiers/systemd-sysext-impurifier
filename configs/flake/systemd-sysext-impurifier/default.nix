# SPDX-License-Identifier: MIT
{ ... }:
{ lib, inputs, ... }: {
  flake.lib = lib.mkForce {
    systemd-sysext-impurifier =
      { pkgs }:
      import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
    in
    {
      packages = {
        default = impurifier.adapter;
        adapter = impurifier.adapter;
        boot-unit = impurifier.bootUnit;
        hello-extension = impurifier.makeExtension {
          applications = [
            {
              pkg = pkgs.hello;
              offline = true;
            }
          ];
        };
      };
      formatter = pkgs.nixfmt-tree;
      checks = (import ../../../tests { inherit pkgs impurifier; }) // {
        bundled-vm =
          (import ../../../tests {
            inherit pkgs;
            bundled = true;
            impurifier = impurifier // {
              makeExtension =
                args:
                impurifier.makeExtension (
                  args
                  // {
                    bundledNixStore = "${
                      import (inputs.impurifier + "/tests/static-nix.nix") { inherit pkgs; }
                    }/bin/nix-store";
                    bundledNixNotices = [ "${pkgs.nix.src}/COPYING" ];
                  }
                );
            };
          }).vm;
      };
    };
}
