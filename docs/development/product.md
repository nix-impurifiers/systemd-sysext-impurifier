# Product

Use real systemd extension images, not package-script emulation. Native sysext
owns the merged /usr view; the shared engine owns Nix profile generations.
Original code is MIT. Dependencies and native Nix provisioning are user policy;
an installer is deferred. See ../../README.md for API, ownership and boot flow.
