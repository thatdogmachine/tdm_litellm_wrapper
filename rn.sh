#!/bin/bash
# UNFREE / impure originally but unneeded for redis but left in place regardless
export NIXPKGS_ALLOW_UNFREE=1
CURRENT_DIR="$(pwd)"
nix develop --extra-experimental-features ca-derivations --extra-experimental-features impure-derivations --fallback --impure