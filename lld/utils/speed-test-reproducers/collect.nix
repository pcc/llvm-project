# This is a Nix recipe for collecting reproducers for benchmarking purposes in a
# reproducible way. It works by injecting a linker wrapper that embeds a
# reproducer tarball into a non-allocated section of every linked object, which
# generally causes them to be smuggled out of the build tree in a section of the
# final binaries. In principle, this technique should let us collect reproducers
# from any project packaged by Nix without project-specific knowledge, but as
# you can see below, many interesting ones need a few hacks.
#
# If you have Nix installed, you can collect a reproducer with a variant of
# the following commands:
#
# TMPDIR=/var/tmp nix-build collect.nix --attr x86_64.chromium
# llvm-objcopy -O binary --only-section=.lld_repro --set-section-flags .lld_repro=alloc result/libexec/chromium/chromium repro.tar.gz
# tar xzf repro.tar.gz
#
# This will result in building Chromium, which will take some time, and if
# you build for a non-native target it will also build most of the dependencies.
# We will eventually publish the tarballs to make this easier to use.
#
# The following projects have been tested successfully:
# - chrome (native only, cross builds fail building the qtbase dependency)
# - firefox (all targets)
# - linux-kernel (all targets, requires patched nixpkgs)
# - ladybird (native only, same problem as chromium)
# - llvm (all targets)

{
  nixpkgsDir ? fetchTarball "https://github.com/NixOS/nixpkgs/archive/25c2561fdf299c850b8c7cdfaa09d0a3f2bc2e89.tar.gz",
  nixpkgs ? import nixpkgsDir,
}:
let
  reproducerPkgs =
    crossSystem:
    let
      pkgs = nixpkgs { inherit crossSystem; };
      # Wraps the given stdenv and lld package into a variant that collects
      # the reproducer.
      reproducerCollectingStdenv =
        stdenv: lld:
        let
          bintools = stdenv.cc.bintools.override {
            extraBuildCommands = ''
              wrap ${stdenv.cc.targetPrefix}nix-wrap-lld ${nixpkgsDir}/pkgs/build-support/bintools-wrapper/ld-wrapper.sh ${lld}/bin/ld.lld
              substituteAll ${./ld-wrapper.sh} $out/bin/${stdenv.cc.targetPrefix}ld
              chmod +x $out/bin/${stdenv.cc.targetPrefix}ld
              substituteAll ${./ld-wrapper.sh} $out/bin/${stdenv.cc.targetPrefix}ld.lld
              chmod +x $out/bin/${stdenv.cc.targetPrefix}ld.lld
            '';
          };
        in
        stdenv.override (old: {
          allowedRequisites = null;
          cc = stdenv.cc.override { inherit bintools; };
        });
      withReproducerCollectingStdenv = pkg: pkg.override {
        stdenv = reproducerCollectingStdenv pkgs.stdenv pkgs.lld;
      };
      withReproducerCollectingClangStdenv = pkg: pkg.override {
        clangStdenv = reproducerCollectingStdenv pkgs.clangStdenv pkgs.lld;
      };
    in
    {
      # For benchmarking the linker we want to disable LTO as otherwise we would
      # just be benchmarking the LLVM optimizer. Also, we generally want the
      # package to use the regular stdenv in order to simplify wrapping it.
      # Firefox normally uses the rustc stdenv but uses the regular one if
      # LTO is disabled so we kill two birds with one stone by disabling it.
      # Chromium uses the rustc stdenv unconditionally so we need the stuff
      # below to make sure that it finds our wrapped stdenv.
      chrome =
        (pkgs.chromium.override {
          newScope =
            extra:
            pkgs.newScope (
              extra
              // {
                pkgsBuildBuild = {
                  pkg-config = pkgs.pkgsBuildBuild.pkg-config;
                  rustc = {
                    llvmPackages = rec {
                      stdenv = reproducerCollectingStdenv pkgs.pkgsBuildBuild.rustc.llvmPackages.stdenv pkgs.pkgsBuildBuild.rustc.llvmPackages.lld;
                      bintools = stdenv.cc.bintools;
                    };
                  };
                };
              }
            );
          pkgs = {
            rustc = {
              llvmPackages = {
                stdenv = reproducerCollectingStdenv pkgs.rustc.llvmPackages.stdenv pkgs.rustc.llvmPackages.lld;
              };
            };
          };
        }).browser.overrideAttrs
          (old: {
            configurePhase =
              old.configurePhase
              + ''
                echo use_thin_lto = false >> out/Release/args.gn
                echo is_cfi = false >> out/Release/args.gn
              '';
          });
      firefox = (withReproducerCollectingStdenv pkgs.firefox-unwrapped).override {
        ltoSupport = false;
        pgoSupport = false;
      };
      # Won't work until https://github.com/NixOS/nixpkgs/pull/390631 lands.
      # Can replace above line with
      #   nixpkgsDir ? fetchTarball "https://github.com/NixOS/nixpkgs/archive/fbc5923fb30c7e1957a729f19f22968083fb473f.tar.gz",
      # for testing with that PR.
      linux-kernel = (withReproducerCollectingStdenv pkgs.linux_latest).dev;
      ladybird = withReproducerCollectingStdenv pkgs.ladybird;
      llvm = withReproducerCollectingStdenv pkgs.llvm;
      webkitgtk = withReproducerCollectingClangStdenv pkgs.webkitgtk;
    };
in
{
  x86_64 = reproducerPkgs { config = "x86_64-unknown-linux-gnu"; };
  aarch64 = reproducerPkgs { config = "aarch64-unknown-linux-gnu"; };
  riscv64 = reproducerPkgs { config = "riscv64-unknown-linux-gnu"; };
}
