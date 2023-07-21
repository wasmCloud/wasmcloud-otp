{
  nixConfig.extra-substituters = [
    "https://wasmcloud.cachix.org"
    "https://nix-community.cachix.org"
    "https://cache.garnix.io"
  ];
  nixConfig.extra-trusted-public-keys = [
    "wasmcloud.cachix.org-1:9gRBzsKh+x2HbVVspreFg/6iFRiD4aOcUQfXVDl3hiM="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];

  inputs.crane.inputs.nixpkgs.follows = "nixpkgs";
  inputs.crane.url = github:rvolosatovs/crane/feat/wit;
  inputs.erlang-aarch64-apple-darwin-mac.flake = false;
  inputs.erlang-aarch64-apple-darwin-mac.url = https://github.com/rvolosatovs/otp/releases/download/OTP-25.3.2/erts-aarch64-apple-darwin-mac.tar.gz;
  inputs.erlang-x86_64-apple-darwin-mac.flake = false;
  inputs.erlang-x86_64-apple-darwin-mac.url = https://github.com/rvolosatovs/otp/releases/download/OTP-25.3.2/erts-x86_64-apple-darwin-mac.tar.gz;
  inputs.erlang.flake = false;
  inputs.erlang.url = github:erlang/otp/OTP-25.3.2;
  inputs.erts-x86_64-pc-windows-msvc.flake = false;
  inputs.erts-x86_64-pc-windows-msvc.url = https://github.com/erlang/otp/releases/download/OTP-25.3.2/otp_win64_25.3.2.exe;
  inputs.fenix.url = github:nix-community/fenix/monthly;
  inputs.nix-log.inputs.nixify.follows = "nixify";
  inputs.nix-log.url = github:rvolosatovs/nix-log;
  inputs.nixify.inputs.crane.follows = "crane";
  inputs.nixify.inputs.fenix.follows = "fenix";
  inputs.nixify.inputs.nix-log.follows = "nix-log";
  inputs.nixify.inputs.nixlib.follows = "nixlib";
  inputs.nixify.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixify.url = github:rvolosatovs/nixify;
  inputs.nixlib.url = github:nix-community/nixpkgs.lib;
  inputs.nixpkgs-old.url = github:NixOS/nixpkgs/nixpkgs-20.09-darwin;
  inputs.nixpkgs.url = github:NixOS/nixpkgs/nixpkgs-unstable;

  # These inputs are "virtual", exposed just to be overriden
  inputs.hostcore_wasmcloud_native-aarch64-apple-darwin-mac.flake = false;
  inputs.hostcore_wasmcloud_native-aarch64-apple-darwin-mac.url = file:/dev/null;
  inputs.hostcore_wasmcloud_native-x86_64-apple-darwin-mac.flake = false;
  inputs.hostcore_wasmcloud_native-x86_64-apple-darwin-mac.url = file:/dev/null;
  inputs.hostcore_wasmcloud_native-x86_64-pc-windows-msvc.flake = false;
  inputs.hostcore_wasmcloud_native-x86_64-pc-windows-msvc.url = file:/dev/null;

  outputs = {
    self,
    erlang,
    erlang-aarch64-apple-darwin-mac,
    erlang-x86_64-apple-darwin-mac,
    erts-x86_64-pc-windows-msvc,
    fenix,
    hostcore_wasmcloud_native-aarch64-apple-darwin-mac,
    hostcore_wasmcloud_native-x86_64-apple-darwin-mac,
    hostcore_wasmcloud_native-x86_64-pc-windows-msvc,
    nix-log,
    nixify,
    nixlib,
    nixpkgs-old,
    ...
  }:
    with nixlib.lib;
    with builtins;
    with nix-log.lib;
    with nixify.lib;
    with nixify.lib.rust.targets; let
      version = "0.62.1";

      otpVersion = "25.3.2";

      mkStdenv = {
        pkgs,
        pkgsCross ? pkgs,
      }: let
        pkgsOld = nixpkgs-old.legacyPackages.${pkgs.stdenv.buildPlatform.system};
      in
        if pkgsCross.stdenv.hostPlatform.isGnu && pkgsCross.stdenv.hostPlatform.isAarch64
        then let
          cc =
            if pkgs.stdenv.buildPlatform.isGnu && pkgs.stdenv.buildPlatform.isAarch64
            # Pull in newer gcc to enable support for aarch64 atomics (e.g. `__aarch64_ldadd4_relax`)
            then pkgsOld.gcc10Stdenv.cc
            else pkgsOld.pkgsCross.aarch64-multiplatform.gcc10Stdenv.cc;
        in
          pkgsCross.overrideCC pkgsCross.stdenv cc
        else if pkgsCross.stdenv.hostPlatform.isGnu && pkgsCross.stdenv.hostPlatform.isx86_64
        then let
          cc =
            if pkgs.stdenv.buildPlatform.isGnu && pkgs.stdenv.buildPlatform.isx86_64
            then pkgsOld.stdenv.cc
            else pkgsOld.pkgsCross.gnu64.stdenv.cc;
        in
          pkgsCross.overrideCC pkgsCross.stdenv cc
        else pkgsCross.stdenv;

      # Given a package set, constructs and attribute set of packages, overlays, etc.
      # See `nixify.lib.rust.mkAttrs` https://github.com/rvolosatovs/nixify/blob/0dc7973067d597457452a050de9b03d979564df4/lib/rust/mkAttrs.nix#L423-L435
      # mkNifAttrs :: PackageSet -> AttributeSet
      mkNifAttrs = rust.mkAttrs {
        src = ./host_core/native/hostcore_wasmcloud_native;

        doCheck = false;

        targets.armv7-unknown-linux-musleabihf = false;
        targets.wasm32-wasi = false;

        buildOverrides = {
          pkgs,
          pkgsCross ? pkgs,
          ...
        } @ args: {
          depsBuildBuild ? [],
          buildInputs ? [],
          CARGO_TARGET ? pkgsCross.stdenv.hostPlatform.config,
          ...
        }: let
          crossPlatform = pkgsCross.stdenv.hostPlatform;

          crossStdenv = mkStdenv {
            inherit
              pkgs
              pkgsCross
              ;
          };
        in
          {
            buildInputs =
              buildInputs
              ++ optional pkgs.stdenv.buildPlatform.isDarwin pkgs.libiconv;

            depsBuildBuild =
              depsBuildBuild
              ++ [
                pkgs.protobuf # build dependency of prost-build v0.9.0
              ]
              ++ optionals pkgsCross.stdenv.hostPlatform.isDarwin [
                pkgsCross.darwin.apple_sdk.frameworks.CoreFoundation
                pkgsCross.libiconv
              ];
          }
          // optionalAttrs crossPlatform.isGnu {
            "CC_${CARGO_TARGET}" = "${crossStdenv.cc}/bin/${crossStdenv.cc.targetPrefix}cc";
            "CARGO_TARGET_${toUpper (replaceStrings ["-"] ["_"] CARGO_TARGET)}_LINKER" = "${crossStdenv.cc}/bin/${crossStdenv.cc.targetPrefix}cc";

            meta.broken = crossPlatform.isGnu && pkgs.stdenv.buildPlatform.isDarwin; # downgrading glibc breaks Darwin support here
          };
      };

      # mkErlang :: AttributeSet -> Package
      mkErlang = {
        pkgs,
        pkgsCross ? pkgs,
      }: let
        openssl = pkgsCross.pkgsStatic.openssl_3_0.override {
          static = true; # upstream darwin builds are not actually static, force static for all
        };

        opensslLib = getOutput "out" openssl;
        opensslIncl = getDev openssl;

        nativeErlang = pkgs.erlang_25;
        yielding_c_fun = "${nativeErlang}/lib/erlang/erts-13.2.1/bin/yielding_c_fun";

        nativeBuildInputs = [
          pkgs.autoconf
          pkgs.gnum4
          pkgs.libxml2
          pkgs.libxslt
          pkgs.makeWrapper
          pkgs.perl
        ];

        crossPlatform = pkgsCross.stdenv.hostPlatform;
        stdenv = mkStdenv {
          inherit
            pkgs
            pkgsCross
            ;
        };

        configureFlags =
          [
            "--disable-dynamic-ssl-lib"
            "--enable-builtin-zlib"
            "--enable-deterministic-build"
            "--enable-hipe"
            "--enable-kernel-poll"
            "--enable-smp-support"
            "--enable-static-drivers"
            "--enable-static-nifs"
            "--enable-threads"
            "--with-ssl-incl=${opensslIncl}"
            "--with-ssl=${opensslLib}"
            "--without-cdv"
            "--without-debugger"
            "--without-et"
            "--without-javac"
            "--without-observer"
            "--without-odbc"
            "--without-termcap"
            "--without-wx"
            "LIBS=${opensslLib}/lib/libcrypto.a"
          ]
          ++ optional crossPlatform.isDarwin "--enable-darwin-64bit";
      in
        stdenv.mkDerivation (
          {
            inherit
              nativeBuildInputs
              ;

            src = erlang;
            name = "erlang";

            dontInstall = true;
            dontPatchShebangs = true;

            # NOTE: parallel Linux builds seems to be flaky
            preConfigure = optionalString crossPlatform.isDarwin ''
              export MAKEFLAGS+=" -j$NIX_BUILD_CORES"
            '';

            configureFlags =
              configureFlags
              ++ optionals crossPlatform.isDarwin [
                "AR=/usr/bin/ar"
                "CC=/usr/bin/clang"
                "CXX=/usr/bin/clang++"
                "LD=/usr/bin/ld"
                "RANLIB=/usr/bin/ranlib"
              ];

            depsBuildBuild = [
              openssl
            ];

            postPatch = ''
              patchShebangs make
            '';

            configureScript = "./otp_build configure";
            buildPhase = "./otp_build release -a $out";
          }
          // optionalAttrs crossPlatform.isLinux {
            NIX_CFLAGS_COMPILE = [
              "-static-libgcc"
              "-static-libstdc++"
            ];
            NIX_CFLAGS_LINK = [
              "-static-libgcc"
              "-static-libstdc++"
            ];
          }
          // optionalAttrs (pkgs.stdenv.hostPlatform.config != crossPlatform.config) {
            erl_xcomp_sysroot = pkgs.symlinkJoin {
              name = "erlang-${crossPlatform.config}-sysroot";
              paths = [
                opensslLib
                opensslIncl
              ];
            };

            configureFlags =
              configureFlags
              ++ optional (crossPlatform.isDarwin && crossPlatform.isAarch64) "--xcomp-conf=xcomp/erl-xcomp-aarch64-darwin.conf";

            postPatch = assert pathExists yielding_c_fun; ''
              substituteInPlace erts/emulator/Makefile.in \
                --replace 'YCF_EXECUTABLE_PATH=`utils/find_cross_ycf`' 'YCF_EXECUTABLE_PATH=${yielding_c_fun}'
            '';

            nativeBuildInputs =
              nativeBuildInputs
              ++ [
                nativeErlang
              ];
          }
        );

      mkBeam = pkgs: pkgs.beam.packagesWith pkgs.beam.interpreters.erlang;

      mkErlangEnv = {SECRET_KEY_BASE ? ""}:
        {
          LANG = "C.UTF-8";
          LC_TYPE = "C.UTF-8";
        }
        // optionalAttrs (SECRET_KEY_BASE != "") {
          inherit
            SECRET_KEY_BASE
            ;
        };

      mkMixDeps = {
        installPhase ? null,
        pkgs,
        pname,
        SECRET_KEY_BASE ? "",
        sha256 ? fakeHash,
        src,
        version,
      }:
        (mkBeam pkgs).fetchMixDeps ({
            inherit
              sha256
              src
              version
              ;
            pname = "mix-${pname}-deps";

            env = mkErlangEnv {
              inherit
                SECRET_KEY_BASE
                ;
            };

            dontFixup = true;
          }
          // optionalAttrs (installPhase != null) {
            inherit installPhase;
          });

      # mkBurritoBuildInputs :: PackageSet -> [ Package ]
      mkBurritoBuildInputs = pkgs: [
        pkgs.p7zip
        pkgs.xz
        pkgs.zig_0_10
      ];

      # mkBurrito :: AttributeSet -> Package
      mkBurrito = {
        buildInputs ? [],
        BURRITO_TARGET ? "",
        esbuild ? null,
        mixFodDeps,
        pkgs,
        pname,
        preBuild ? null,
        preConfigure ? null,
        sass ? null,
        SECRET_KEY_BASE ? "",
        src,
        version,
      }: let
        beam = mkBeam pkgs;

        packages = self.packages.${pkgs.stdenv.system};

        NIF_AARCH64_DARWIN = "${hostcore_wasmcloud_native-aarch64-apple-darwin-mac}/lib/libhostcore_wasmcloud_native.dylib";
        NIF_X86_64_DARWIN = "${hostcore_wasmcloud_native-x86_64-apple-darwin-mac}/lib/libhostcore_wasmcloud_native.dylib";
        NIF_X86_64_WINDOWS = "${hostcore_wasmcloud_native-x86_64-pc-windows-msvc}/lib/hostcore_wasmcloud_native.dll";

        env =
          mkErlangEnv {
            inherit
              SECRET_KEY_BASE
              ;
          }
          // optionalAttrs (sass != null) {
            MIX_SASS_PATH = "${sass}/bin/sass";
          }
          // optionalAttrs (esbuild != null) {
            MIX_ESBUILD_PATH = "${esbuild}/bin/esbuild";
          }
          // optionalAttrs (BURRITO_TARGET != "") {
            inherit
              BURRITO_TARGET
              ;
          }
          // filterAttrs (k: _: BURRITO_TARGET == "" || hasSuffix (toUpper BURRITO_TARGET) k) {
            ERTS_AARCH64_DARWIN = packages.erts-aarch64-apple-darwin-mac;
            ERTS_AARCH64_LINUX_GNU = packages.erts-aarch64-unknown-linux-gnu-fhs;
            ERTS_AARCH64_LINUX_MUSL = packages.erts-aarch64-unknown-linux-musl-fhs;
            ERTS_X86_64_DARWIN = packages.erts-x86_64-apple-darwin-mac;
            ERTS_X86_64_WINDOWS = packages.erts-x86_64-pc-windows-msvc;
            ERTS_X86_64_LINUX_GNU = packages.erts-x86_64-unknown-linux-gnu-fhs;
            ERTS_X86_64_LINUX_MUSL = packages.erts-x86_64-unknown-linux-musl-fhs;

            NIF_AARCH64_DARWIN = assert pathExists NIF_AARCH64_DARWIN; NIF_AARCH64_DARWIN;
            NIF_AARCH64_LINUX_GNU = "${packages.hostcore_wasmcloud_native-aarch64-unknown-linux-gnu-fhs}/lib/libhostcore_wasmcloud_native.so";
            NIF_AARCH64_LINUX_MUSL = "${packages.hostcore_wasmcloud_native-aarch64-unknown-linux-musl-fhs}/lib/libhostcore_wasmcloud_native.so";
            NIF_X86_64_DARWIN = assert pathExists NIF_X86_64_DARWIN; NIF_X86_64_DARWIN;
            NIF_X86_64_WINDOWS = assert pathExists NIF_X86_64_WINDOWS; NIF_X86_64_WINDOWS;
            NIF_X86_64_LINUX_GNU = "${packages.hostcore_wasmcloud_native-x86_64-unknown-linux-gnu-fhs}/lib/libhostcore_wasmcloud_native.so";
            NIF_X86_64_LINUX_MUSL = "${packages.hostcore_wasmcloud_native-x86_64-unknown-linux-musl-fhs}/lib/libhostcore_wasmcloud_native.so";
          };
      in
        trace' "mkBurrito" {
          inherit
            BURRITO_TARGET
            env
            esbuild
            pname
            sass
            SECRET_KEY_BASE
            src
            version
            ;
        }
        beam.mixRelease (
          {
            inherit
              env
              mixFodDeps
              pname
              src
              version
              ;
            dontFixup = true;

            buildInputs = mkBurritoBuildInputs pkgs ++ buildInputs;

            buildPhase = ''
              runHook preBuild

              export HOME=$(mktemp -d)
              mix release --no-deps-check

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p $out/bin
              cp ./burrito_out/* $out/bin

              runHook postInstall
            '';
          }
          // optionalAttrs (preConfigure != null) {
            inherit preConfigure;
          }
          // optionalAttrs (preBuild != null) {
            inherit preBuild;
          }
        );

      mkBurritoPackages = {
        buildInputs ? [],
        esbuild ? null,
        mixFodDeps,
        pkgs,
        pname,
        preBuild ? null,
        preConfigure ? null,
        sass ? null,
        SECRET_KEY_BASE ? "",
        src,
        version,
      } @ args: {
        "${pname}-burrito" = mkBurrito args;
        "${pname}-burrito-aarch64-darwin" = mkBurrito (args
          // {
            BURRITO_TARGET = "aarch64_darwin";
          });
        "${pname}-burrito-aarch64-linux-gnu" = mkBurrito (args
          // {
            BURRITO_TARGET = "aarch64_linux_gnu";
          });
        "${pname}-burrito-aarch64-linux-musl" = mkBurrito (args
          // {
            BURRITO_TARGET = "aarch64_linux_musl";
          });
        "${pname}-burrito-x86_64-darwin" = mkBurrito (args
          // {
            BURRITO_TARGET = "x86_64_darwin";
          });
        "${pname}-burrito-x86_64-linux-gnu" = mkBurrito (args
          // {
            BURRITO_TARGET = "x86_64_linux_gnu";
          });
        "${pname}-burrito-x86_64-linux-musl" = mkBurrito (args
          // {
            BURRITO_TARGET = "x86_64_linux_musl";
          });
        "${pname}-burrito-x86_64-windows" = mkBurrito (args
          // {
            BURRITO_TARGET = "x86_64_windows";
          });
      };
    in
      mkFlake {
        overlays = [
          fenix.overlays.default
        ];

        withPackages = {
          packages,
          pkgs,
          ...
        }: let
          interpreters.aarch64-unknown-linux-gnu = "/lib/ld-linux-aarch64.so.1";
          interpreters.aarch64-unknown-linux-musl = "/lib/ld-musl-aarch64.so.1";
          interpreters.x86_64-unknown-linux-gnu = "/lib64/ld-linux-x86-64.so.2";
          interpreters.x86_64-unknown-linux-musl = "/lib/ld-musl-x86_64.so.1";

          nifAttrs = mkNifAttrs pkgs;

          mkFHS = {
            name,
            src,
            interpreter,
          }:
            pkgs.stdenv.mkDerivation {
              inherit
                name
                src
                ;

              buildInputs = [
                pkgs.patchelf
              ];

              dontBuild = true;
              dontFixup = true;

              installPhase = ''
                runHook preInstall

                for p in $(find . -type f); do
                  # https://en.wikipedia.org/wiki/Executable_and_Linkable_Format#File_header
                  if head -c 4 $p | grep $'\x7FELF' > /dev/null; then
                    patchelf --set-rpath /lib $p || true
                    patchelf --set-interpreter ${interpreter} $p || true
                  fi
                done

                mkdir -p $out
                cp -R * $out

                runHook postInstall
              '';
            };

          mkMac = {
            name,
            src,
          }:
            pkgs.stdenv.mkDerivation {
              inherit
                name
                src
                ;

              buildInputs = [
                pkgs.darwin.cctools
              ];

              dontBuild = true;
              dontFixup = true;

              installPhase = ''
                runHook preInstall

                for p in $(find . -type f); do
                  # https://en.wikipedia.org/wiki/Mach-O#Mach-O_header
                  case $(head -c 4 $p | od -An -t x1 | tr -d ' ') in
                    feedface | cefaedfe | feedfacf | cffaedfe)
                        for lib in $(otool -L $p | tail -n +1 | grep -v $p | grep ${storeDir} | cut -f 2 | cut -d ' ' -f 1); do
                            name=$(cut -d '/' -f 2- <<< ''${lib#${storeDir}/})
                            name=''${name#lib/}
                            case $name in
                                libiconv.dylib)
                                    install_name_tool -change "$lib"  '/usr/lib/libiconv.2.dylib' "$p" >&2
                                    ;;
                                *)
                                    install_name_tool -change "$lib" "/usr/lib/$name" "$p" >&2
                                    ;;
                            esac
                        done
                    ;;
                  esac
                done

                mkdir -p $out
                cp -R * $out

                runHook postInstall
              '';

              # By some reason, binaries with paths changed via `install_name_tool` fail to load on aarch64 Macs
              # TODO: Fix it or at least figure out the reason for the runtime failure
              meta.broken = true;
              meta.platforms = platforms.darwin;
            };

          # Partially-applied `mkErlang`, which takes an optional cross package set as argument
          # mkErlang' :: AttributeSet -> Package
          mkErlang' = {pkgsCross ? pkgs}:
            mkErlang {
              inherit
                pkgs
                pkgsCross
                ;
            };
          erlang = mkErlang' {};
          erlang-aarch64-unknown-linux-gnu = mkErlang' (optionalAttrs (pkgs.stdenv.hostPlatform.config != aarch64-unknown-linux-gnu) {
            pkgsCross = pkgs.pkgsCross.aarch64-multiplatform;
          });
          erlang-aarch64-unknown-linux-musl = mkErlang' (optionalAttrs (pkgs.stdenv.hostPlatform.config != aarch64-unknown-linux-musl) {
            pkgsCross = pkgs.pkgsCross.aarch64-multiplatform-musl;
          });
          erlang-x86_64-unknown-linux-gnu = mkErlang' (optionalAttrs (pkgs.stdenv.hostPlatform.config != x86_64-unknown-linux-gnu) {
            pkgsCross = pkgs.pkgsCross.gnu64;
          });
          erlang-x86_64-unknown-linux-musl = mkErlang' (optionalAttrs (pkgs.stdenv.hostPlatform.config != x86_64-unknown-linux-musl) {
            pkgsCross = pkgs.pkgsCross.musl64;
          });

          erlang-aarch64-unknown-linux-gnu-fhs = mkFHS {
            name = "erlang-aarch64-unknown-linux-gnu-fhs";
            src = erlang-aarch64-unknown-linux-gnu;
            interpreter = interpreters.aarch64-unknown-linux-gnu;
          };
          erlang-aarch64-unknown-linux-musl-fhs = mkFHS {
            name = "erlang-aarch64-unknown-linux-musl-fhs";
            src = erlang-aarch64-unknown-linux-musl;
            interpreter = interpreters.aarch64-unknown-linux-musl;
          };
          erlang-x86_64-unknown-linux-gnu-fhs = mkFHS {
            name = "erlang-x86_64-unknown-linux-gnu-fhs";
            src = erlang-x86_64-unknown-linux-gnu;
            interpreter = interpreters.x86_64-unknown-linux-gnu;
          };
          erlang-x86_64-unknown-linux-musl-fhs = mkFHS {
            name = "erlang-x86_64-unknown-linux-musl-fhs";
            src = erlang-x86_64-unknown-linux-musl;
            interpreter = interpreters.x86_64-unknown-linux-musl;
          };

          mkErts = {
            name,
            erlang,
          }:
            pkgs.stdenv.mkDerivation {
              name = "${name}.tar.gz";
              src = erlang;

              buildInputs = [
                pkgs.gnutar
              ];

              dontBuild = true;

              installPhase = ''
                tar czf $out --transform 's,^\.,./otp-${otpVersion},' -C $src .
              '';
            };

          erts-aarch64-apple-darwin-mac = mkErts {
            name = "erts-aarch64-apple-darwin-mac";
            erlang = erlang-aarch64-apple-darwin-mac;
          };
          erts-aarch64-unknown-linux-gnu = mkErts {
            name = "erts-aarch64-unknown-linux-gnu";
            erlang = erlang-aarch64-unknown-linux-gnu;
          };
          erts-aarch64-unknown-linux-gnu-fhs = mkErts {
            name = "erts-aarch64-unknown-linux-gnu-fhs";
            erlang = erlang-aarch64-unknown-linux-gnu-fhs;
          };
          erts-aarch64-unknown-linux-musl = mkErts {
            name = "erts-aarch64-unknown-linux-musl";
            erlang = erlang-aarch64-unknown-linux-musl;
          };
          erts-aarch64-unknown-linux-musl-fhs = mkErts {
            name = "erts-aarch64-unknown-linux-musl-fhs";
            erlang = erlang-aarch64-unknown-linux-musl-fhs;
          };

          erts-x86_64-apple-darwin-mac = mkErts {
            name = "erts-x86_64-apple-darwin-mac";
            erlang = erlang-x86_64-apple-darwin-mac;
          };
          erts-x86_64-unknown-linux-gnu = mkErts {
            name = "erts-x86_64-unknown-linux-gnu";
            erlang = erlang-x86_64-unknown-linux-gnu;
          };
          erts-x86_64-unknown-linux-gnu-fhs = mkErts {
            name = "erts-x86_64-unknown-linux-gnu-fhs";
            erlang = erlang-x86_64-unknown-linux-gnu-fhs;
          };
          erts-x86_64-unknown-linux-musl = mkErts {
            name = "erts-x86_64-unknown-linux-musl";
            erlang = erlang-x86_64-unknown-linux-musl;
          };
          erts-x86_64-unknown-linux-musl-fhs = mkErts {
            name = "erts-x86_64-unknown-linux-musl-fhs";
            erlang = erlang-x86_64-unknown-linux-musl-fhs;
          };

          hostcorePkgs = let
            src = ./host_core;
            pname = "host_core";
            mixFodDeps = mkMixDeps {
              inherit
                pkgs
                pname
                src
                version
                ;
              sha256 = "sha256-19an3Oh5VRcgXCh8nlo0hhhRc/a2hmnUe0nIJUR0fSU=";
            };
          in
            mkBurritoPackages {
              inherit
                mixFodDeps
                pkgs
                pname
                src
                version
                ;
            };

          wasmcloudPkgs = let
            src = ./.;
            pname = "wasmcloud_host";
            SECRET_KEY_BASE = let
              secret = getEnv "SECRET_KEY_BASE";
            in
              if secret == ""
              then warn "`SECRET_KEY_BASE` not set (do not forget to use `--impure`), using insecure default key" "3ImiTAMO0TTD7wrACHrCA+ggkzpw6zGWvE3gtQwlXE6vmnDT9yGP5/WKpLWEJ8fF"
              else throw "'${secret}'";
            mixFodDeps = mkMixDeps {
              inherit
                pkgs
                pname
                SECRET_KEY_BASE
                src
                version
                ;
              sha256 = "sha256-278V/aNbMeTRguIqFiwZnZwFcaOCbJELgxboqApIk9E=";
              installPhase = ''
                runHook preInstall

                cd ./host_core
                mix deps.get ''${MIX_ENV:+--only $MIX_ENV}

                cd ../wasmcloud_host
                mix deps.get ''${MIX_ENV:+--only $MIX_ENV}

                find "$TEMPDIR/deps" -path '*/.git/*' -a ! -name HEAD -exec rm -rf {} +
                cp -r --no-preserve=mode,ownership,timestamps $TEMPDIR/deps $out

                runHook postInstall
              '';
            };
          in
            mkBurritoPackages {
              inherit
                mixFodDeps
                pkgs
                pname
                SECRET_KEY_BASE
                src
                version
                ;
              inherit
                (pkgs)
                sass
                esbuild
                ;

              buildInputs = [
                pkgs.esbuild
                pkgs.sass
              ];

              preConfigure = ''
                cd ./wasmcloud_host
                ln -s $MIX_DEPS_PATH ./deps
              '';

              preBuild = ''
                mkdir -p ./priv/static/assets

                mix do deps.loadpaths --no-deps-check, sass default assets/css/app.scss ./priv/static/assets/app.css
                mix do deps.loadpaths --no-deps-check, assets.deploy

                cp -r assets/static/* ./priv/static/
                cp -r assets/css/coreui ./priv/static/assets/coreui
              '';
            };
        in
          fix (
            self':
              packages
              // {
                inherit
                  erlang
                  erlang-aarch64-unknown-linux-gnu
                  erlang-aarch64-unknown-linux-gnu-fhs
                  erlang-aarch64-unknown-linux-musl
                  erlang-aarch64-unknown-linux-musl-fhs
                  erlang-x86_64-unknown-linux-gnu
                  erlang-x86_64-unknown-linux-gnu-fhs
                  erlang-x86_64-unknown-linux-musl
                  erlang-x86_64-unknown-linux-musl-fhs
                  erts-aarch64-apple-darwin-mac
                  erts-aarch64-unknown-linux-gnu
                  erts-aarch64-unknown-linux-gnu-fhs
                  erts-aarch64-unknown-linux-musl
                  erts-aarch64-unknown-linux-musl-fhs
                  erts-x86_64-apple-darwin-mac
                  erts-x86_64-unknown-linux-gnu
                  erts-x86_64-unknown-linux-gnu-fhs
                  erts-x86_64-unknown-linux-musl
                  erts-x86_64-unknown-linux-musl-fhs
                  ;

                erts-x86_64-pc-windows-msvc = pkgs.stdenv.mkDerivation {
                  name = "erts-x86_64-pc-windows-msvc.exe";
                  src = erts-x86_64-pc-windows-msvc;

                  dontUnpack = true;
                  dontBuild = true;

                  installPhase = ''
                    install $src $out
                  '';
                };

                hostcore_wasmcloud_native-aarch64-unknown-linux-gnu-fhs = mkFHS {
                  name = "hostcore_wasmcloud_native-aarch64-unknown-linux-gnu-fhs";
                  src = self'.hostcore_wasmcloud_native-aarch64-unknown-linux-gnu;
                  interpreter = interpreters.aarch64-unknown-linux-gnu;
                };
                hostcore_wasmcloud_native-aarch64-unknown-linux-musl-fhs = mkFHS {
                  name = "hostcore_wasmcloud_native-aarch64-unknown-linux-musl-fhs";
                  src = self'.hostcore_wasmcloud_native-aarch64-unknown-linux-musl;
                  interpreter = interpreters.aarch64-unknown-linux-musl;
                };
                hostcore_wasmcloud_native-x86_64-unknown-linux-gnu-fhs = mkFHS {
                  name = "hostcore_wasmcloud_native-x86_64-unknown-linux-gnu-fhs";
                  src = self'.hostcore_wasmcloud_native-x86_64-unknown-linux-gnu;
                  interpreter = interpreters.x86_64-unknown-linux-gnu;
                };
                hostcore_wasmcloud_native-x86_64-unknown-linux-musl-fhs = mkFHS {
                  name = "hostcore_wasmcloud_native-x86_64-unknown-linux-musl-fhs";
                  src = self'.hostcore_wasmcloud_native-x86_64-unknown-linux-musl;
                  interpreter = interpreters.x86_64-unknown-linux-musl;
                };
              }
              // optionalAttrs pkgs.stdenv.buildPlatform.isDarwin {
                erlang-aarch64-apple-darwin-mac = mkErlang' (optionalAttrs (pkgs.stdenv.hostPlatform.config != aarch64-apple-darwin) {
                  pkgsCross = pkgs.pkgsCross.aarch64-darwin;
                });
                erts-aarch64-apple-darwin-mac = mkErts {
                  name = "erts-aarch64-apple-darwin-mac";
                  erlang = self'.erlang-aarch64-apple-darwin-mac;
                };
                erlang-x86_64-apple-darwin-mac = mkErlang' (optionalAttrs (pkgs.stdenv.hostPlatform.config != x86_64-apple-darwin) {
                  pkgsCross = pkgs.pkgsCross.x86_64-darwin;
                });
                erts-x86_64-apple-darwin-mac = mkErts {
                  name = "erts-x86_64-apple-darwin-mac";
                  erlang = self'.erlang-x86_64-apple-darwin-mac;
                };
                hostcore_wasmcloud_native-aarch64-apple-darwin-mac = mkMac {
                  name = "hostcore_wasmcloud_native-aarch64-apple-darwin-mac";
                  src = self'.hostcore_wasmcloud_native-aarch64-apple-darwin;
                };
                hostcore_wasmcloud_native-x86_64-apple-darwin-mac = mkMac {
                  name = "hostcore_wasmcloud_native-x86_64-apple-darwin-mac";
                  src = self'.hostcore_wasmcloud_native-x86_64-apple-darwin;
                };
              }
              // nifAttrs.packages
              // hostcorePkgs
              // wasmcloudPkgs
          );

        withDevShells = {
          devShells,
          pkgs,
          ...
        }: let
          nifAttrs = mkNifAttrs pkgs;

          burritoBuildInputs = mkBurritoBuildInputs pkgs;

          build-mac-erts = pkgs.writeShellScriptBin "build-mac-erts" ''
            set -xe

            out=''${1:-_nix/out}
            mkdir -p $out

            nix build -L \
                ${self}\#packages.aarch64-darwin.erts-aarch64-apple-darwin-mac \
                ${self}\#packages.x86_64-darwin.erts-x86_64-apple-darwin-mac \
                -o $out/result

            nix build -L \
                ${self}\#packages.aarch64-darwin.erts-aarch64-apple-darwin-mac \
                -o $out/erts-aarch64-apple-darwin-mac.tar.gz

            nix build -L \
                ${self}\#packages.x86_64-darwin.erts-x86_64-apple-darwin-mac \
                -o $out/erts-x86_64-apple-darwin-mac.tar.gz
          '';

          release = pkgs.writeShellScriptBin "release" (''
              if [ -z $HOSTCORE_WASMCLOUD_NATIVE_AARCH64_APPLE_DARWIN ]; then
                  echo "HOSTCORE_WASMCLOUD_NATIVE_AARCH64_APPLE_DARWIN must be set to a path containing 'lib/libhostcore_wasmcloud_native.dylib'"
                  exit 1
              fi
              if [ -z $HOSTCORE_WASMCLOUD_NATIVE_X86_64_APPLE_DARWIN ]; then
                  echo "HOSTCORE_WASMCLOUD_NATIVE_X86_64_APPLE_DARWIN must be set to a path containing 'lib/libhostcore_wasmcloud_native.dylib'"
                  exit 1
              fi
              if [ -z $HOSTCORE_WASMCLOUD_NATIVE_X86_64_PC_WINDOWS_MSVC ]; then
                  echo "HOSTCORE_WASMCLOUD_NATIVE_X86_64_PC_WINDOWS_MSVC must be set to a path containing 'lib/hostcore_wasmcloud_native.dll'"
                  exit 1
              fi

              set -xe

              out=''${1:-_nix/out}
              mkdir -p $out

              nix build -L \
                  --impure \
                  --override-input hostcore_wasmcloud_native-aarch64-apple-darwin-mac "$HOSTCORE_WASMCLOUD_NATIVE_AARCH64_APPLE_DARWIN" \
                  --override-input hostcore_wasmcloud_native-x86_64-apple-darwin-mac "$HOSTCORE_WASMCLOUD_NATIVE_X86_64_APPLE_DARWIN" \
                  --override-input hostcore_wasmcloud_native-x86_64-pc-windows-msvc "$HOSTCORE_WASMCLOUD_NATIVE_X86_64_PC_WINDOWS_MSVC" \
                  ${self}\#host_core-burrito-aarch64-darwin \
                  ${self}\#host_core-burrito-aarch64-linux-gnu \
                  ${self}\#host_core-burrito-aarch64-linux-musl \
                  ${self}\#host_core-burrito-x86_64-darwin \
                  ${self}\#host_core-burrito-x86_64-linux-gnu \
                  ${self}\#host_core-burrito-x86_64-linux-musl \
                  ${self}\#host_core-burrito-x86_64-windows \
                  ${self}\#wasmcloud_host-burrito-aarch64-darwin \
                  ${self}\#wasmcloud_host-burrito-aarch64-linux-gnu \
                  ${self}\#wasmcloud_host-burrito-aarch64-linux-musl \
                  ${self}\#wasmcloud_host-burrito-x86_64-darwin \
                  ${self}\#wasmcloud_host-burrito-x86_64-linux-gnu \
                  ${self}\#wasmcloud_host-burrito-x86_64-linux-musl \
                  ${self}\#wasmcloud_host-burrito-x86_64-windows \
                  -o $out/result

            ''
            + concatMapStringsSep "\n" (target: ''
              nix build -L \
                  --override-input hostcore_wasmcloud_native-aarch64-apple-darwin-mac "$HOSTCORE_WASMCLOUD_NATIVE_AARCH64_APPLE_DARWIN" \
                  --override-input hostcore_wasmcloud_native-x86_64-apple-darwin-mac "$HOSTCORE_WASMCLOUD_NATIVE_X86_64_APPLE_DARWIN" \
                  --override-input hostcore_wasmcloud_native-x86_64-pc-windows-msvc "$HOSTCORE_WASMCLOUD_NATIVE_X86_64_PC_WINDOWS_MSVC" \
                  ${self}\#host_core-burrito-${target} -o $out/host_core-burrito-${target}

              nix build -L \
                  --impure \
                  --override-input hostcore_wasmcloud_native-aarch64-apple-darwin-mac "$HOSTCORE_WASMCLOUD_NATIVE_AARCH64_APPLE_DARWIN" \
                  --override-input hostcore_wasmcloud_native-x86_64-apple-darwin-mac "$HOSTCORE_WASMCLOUD_NATIVE_X86_64_APPLE_DARWIN" \
                  --override-input hostcore_wasmcloud_native-x86_64-pc-windows-msvc "$HOSTCORE_WASMCLOUD_NATIVE_X86_64_PC_WINDOWS_MSVC" \
                  ${self}\#wasmcloud_host-burrito-${target} -o $out/wasmcloud_host-burrito-${target}
            '') [
              "aarch64-darwin"
              "aarch64-linux-gnu"
              "aarch64-linux-musl"
              "x86_64-darwin"
              "x86_64-linux-gnu"
              "x86_64-linux-musl"
              "x86_64-windows"
            ]);
        in
          extendDerivations {
            env.MIX_ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";
            env.MIX_SASS_PATH = "${pkgs.sass}/bin/sass";

            buildInputs =
              burritoBuildInputs
              ++ [
                nifAttrs.hostRustToolchain

                pkgs.beamPackages.hex
                pkgs.beamPackages.rebar3
                pkgs.elixir_1_14
                pkgs.esbuild
                pkgs.nats-server
                pkgs.sass

                build-mac-erts
                release
              ];
          }
          devShells;
      };
}
