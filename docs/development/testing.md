# Testing

`nix flake check -L` exercises native loop-mounted SquashFS images and overlayfs
inside QEMU, including a real shutdown/restart. The writable Nix store must use
the guest disk rather than tmpfs. The unit-directory fixture dereferences
symlinked directories while retaining actual unit/dependency symlinks, so native
enable/disable and boot ordering are meaningful. Nix and Python are preinstalled.

Public output reference tests must prove application outputs are initially absent;
images carry the closure bytes and discard build-time references. Never replace
a live mounted image in place: stage a new file and rename it atomically.
