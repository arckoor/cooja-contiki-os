{
  description = "Cooja with msp430-gcc";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    nixpkgs-python = {
      url = "github:cachix/nixpkgs-python";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs = {
    nixpkgs,
    flake-utils,
    nixpkgs-python,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };
        gcc4-pkgs = import (fetchTarball {
          url = "https://github.com/NixOS/nixpkgs/archive/0c66dbaee6647abfb4d2774588a0cf0ad8d4f02b.tar.gz";
          sha256 = "sha256:040m9qprszi9x9zbkdjqf35pp7nx7jpama9kicv5ix4pxiiw5ap4";
        }) {inherit system;};

        msp430-patches = pkgs.stdenvNoCC.mkDerivation rec {
          pname = "msp430-patches";
          version = "20120911";
          src = pkgs.fetchzip {
            url = "https://sourceforge.net/projects/mspgcc/files/mspgcc/DEVEL-4.7.x/mspgcc-20120911.tar.bz2";
            hash = "sha256-BWFF4kWrJrSEhtcDQ+jFjVj/j4Zec/uanarnFlojieA=";
          };
          installPhase = ''
            mkdir -p $out
            cp *.patch $out
          '';
        };

        gcc-patches = pkgs.stdenvNoCC.mkDerivation rec {
          name = "gcc-patches";
          src = pkgs.fetchzip {
            url = "https://raw.githubusercontent.com/tgtakaoka/homebrew-mspgcc/master/patches/gcc-4.7.0-patches.tar.xz";
            hash = "sha256-z7E8fEnaBJlKAFhRkhV7KeVDYIHlNNL10TNQZUdUGFY=";
            stripRoot = false;
          };
          installPhase = ''
            mkdir -p $out
            cp *.patch $out
          '';
        };

        msp430-binutils = pkgs.stdenv.mkDerivation rec {
          version = "2.22";
          pname = "msp430-binutils";
          src = pkgs.fetchurl {
            url = "https://ftp.gnu.org/gnu/binutils/binutils-${version}.tar.bz2";
            hash = "sha256-bHr47RyM+bS51ub+CaPh09R5/mOYS6i5smvzVrYxPKk=";
          };
          patches = [
            "${msp430-patches}/msp430-binutils-${version}-20120911.patch"
          ];
          nativeBuildInputs = with pkgs; [
            gmp
            mpfr
            libmpc
            flex
            bison
          ];
          makeFlags = ["MAKEINFO=true"];
          configureFlags = [
            "--target=msp430"
            "--disable-nls"
            "--disable-werror"
          ];
          enableParallelBuilding = true;
        };

        msp430-binutils-symlinked = pkgs.stdenvNoCC.mkDerivation {
          name = "msp430-bintuils-symlinked";
          nativeBuildInputs = [
            msp430-binutils
          ];
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/bin
            for bin in ${msp430-binutils}/bin/msp430-*; do
              base=$(basename $bin)
              targetName=$(echo $base | sed 's/^msp430-//')
              ln -s $bin $out/bin/$targetName
            done
          '';
        };

        msp430-gcc-unwrapped = pkgs.stdenv.mkDerivation rec {
          version = "4.7.0";
          name = "msp430-gcc-unwrapped-${version}";
          src = pkgs.fetchzip {
            url = "http://ftp.gnu.org/gnu/gcc/gcc-${version}/gcc-${version}.tar.bz2";
            hash = "sha256-bXYbSq1z3bVKmfdV/uR+cn9Yg+Y0AxZMkXehLpYnx48=";
          };
          patches = [
            "${msp430-patches}/msp430-gcc-${version}-20120911.patch"
            "${gcc-patches}/gcc-4.7.0_PR-54638.patch"
            "${gcc-patches}/gcc-4.7.0_gperf.patch"
            "${gcc-patches}/gcc-4.7.0_libiberty-multilib.patch"
          ];
          nativeBuildInputs = with pkgs; [
            gmp
            mpfr
            libmpc
            flex
            bison
            msp430-binutils
          ];
          makeFlags = ["MAKEINFO=true"];
          preConfigure = ''
            mkdir build
            cd build
          '';
          configureScript = "../configure";
          configureFlags = [
            "--target=msp430"
            "--enable-languages=c"
            "--disable-nls"
            "--disable-werror"
          ];
          enableParallelBuilding = true;
          NIX_CFLAGS_COMPILE = "-Wno-error -Wno-format-security -Wno-incompatible-pointer-types -g";
        };

        msp430-mcu = pkgs.stdenvNoCC.mkDerivation rec {
          pname = "msp430-mcu";
          version = "20130321";
          src = pkgs.fetchzip {
            url = "https://sourceforge.net/projects/mspgcc/files/msp430mcu/msp430mcu-${version}.tar.bz2";
            hash = "sha256-da7RmEjbRIWw+nYg2k1aobspex/GpYGJS1bwm/7t4Ak=";
          };
          installPhase = ''
            mkdir -p $out/upstream $out/lib $out/analysis
            cp upstream/*h $out/upstream
            cp include/*.h $out/lib
            cp -r analysis/* $out/analysis
          '';
        };

        msp430-libc = pkgs.stdenvNoCC.mkDerivation rec {
          version = "20120716";
          name = "msp430-libc-${version}";
          src = pkgs.fetchzip {
            url = "https://sourceforge.net/projects/mspgcc/files/msp430-libc/msp430-libc-${version}.tar.bz2";
            hash = "sha256-NTLQpFgI1rFSQule/lBLf+ftQ5rsx8HiakQcZuaRvLI=";
          };
          nativeBuildInputs = [
            msp430-binutils
            msp430-binutils-symlinked
            msp430-gcc-unwrapped
            msp430-mcu
          ];
          prePatch = ''
            ls -laFh
            ls -laFh src
            ls -laFh src/stdlib
            cat src/stdlib/malloc.c
          '';
          patches = [
            ./patches/libc.patch
          ];
          makeFlags = ["MAKEINFO=true"];
          buildPhase = ''
            cd src
            make
          '';
          enableParallelBuilding = true;
        };

        msp430-lib = pkgs.stdenvNoCC.mkDerivation {
          name = "msp430-libs";
          nativeBuildInputs = [
            msp430-libc
            msp430-mcu
          ];
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/include $out/lib
            cp ${msp430-mcu}/upstream/* $out/include
            cp ${msp430-mcu}/lib/* $out/include
            cp -r ${msp430-mcu}/analysis/ldscripts $out/lib
            cp ${msp430-mcu}/analysis/msp430mcu.spec $out/lib

            cp -r ${msp430-libc}/msp430/lib/* $out/lib
            cp -r ${msp430-libc}/msp430/include/* $out/include
          '';
        };

        msp430-gcc = pkgs.stdenvNoCC.mkDerivation {
          pname = "msp430-gcc";
          version = msp430-gcc-unwrapped.version;
          nativeBuildInputs = with pkgs; [
            msp430-gcc-unwrapped
            msp430-lib
            makeWrapper
          ];
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/bin
            makeWrapper ${msp430-gcc-unwrapped}/bin/msp430-gcc $out/bin/msp430-gcc \
              --add-flags "-I${msp430-lib}/include -L${msp430-lib}/lib -L${msp430-lib}/lib/ldscripts/msp430f1611" \
              --set LC_ALL C
          '';
        };

        msp430-gdb-unwrapped = gcc4-pkgs.stdenv.mkDerivation rec {
          version = "7.2a";
          name = "msp430-gdb-unwrapped-${version}";
          src = pkgs.fetchzip {
            url = "https://ftp.gnu.org/pub/gnu/gdb/gdb-7.2a.tar.bz2";
            hash = "sha256-En1c84Y6elRfjOeQKrTrrcihgxTQKTJirGMnXi8wGW0=";
          };
          patches = [
            "${msp430-patches}/msp430-gdb-7.2a-20111205.patch"
          ];
          buildInputs = with gcc4-pkgs; [
            texinfo
            ncurses
            gmp
            mpfr
            mpc
            flex
            bison
            zlib
            msp430-binutils
            makeWrapper
          ];
          makeFlags = ["MAKEINFO=true"];
          preConfigure = ''
            mkdir build
            cd build
          '';
          configureScript = "../configure";
          configureFlags = [
            "--target=msp430"
          ];
          enableParallelBuilding = true;
          NIX_CFLAGS_COMPILE = "-Wno-error -Wno-error=format-security";
        };

        msp430-gdb = pkgs.stdenvNoCC.mkDerivation {
          pname = "msp430-gdb";
          version = "7.2a";
          nativeBuildInputs = with pkgs; [
            msp430-gdb-unwrapped
            makeWrapper
          ];
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/bin
            makeWrapper ${msp430-gdb-unwrapped}/bin/msp430-gdb $out/bin/msp430-gdb \
              --set LC_ALL C
          '';
        };

        contiki-os-source = pkgs.stdenv.mkDerivation {
          name = "contiki-os-source";
          src = pkgs.fetchFromGitHub {
            owner = "contiki-os";
            repo = "contiki";
            rev = "32b5b17f674232867c22916bb2e2534c8e9a92ff";
            hash = "sha256-rMSDFbYxtXhCsWGXphjb1qoI0HRU5wet9QUQV9NCySI=";
          };
          installPhase = ''
            mkdir -p $out
            cp -r * $out
          '';
        };

        cooja = pkgs.stdenv.mkDerivation rec {
          pname = "cooja";
          version = "latest";
          src = pkgs.fetchFromGitHub {
            owner = "contiki-os";
            repo = "contiki";
            rev = "32b5b17f674232867c22916bb2e2534c8e9a92ff";
            hash = "sha256-rMSDFbYxtXhCsWGXphjb1qoI0HRU5wet9QUQV9NCySI=";
          };
          mspsim = pkgs.fetchFromGitHub {
            owner = "contiki-os";
            repo = "mspsim";
            rev = "47ae45cb0f36337115e32adb2a5ba0bf6e1e4437";
            hash = "sha256-Notvul48WXj6JxciFmSUVHM2rguVG2t2HO1t8PBipiI=";
          };
          nativeBuildInputs = with pkgs; [
            jdk8
            ant
            makeWrapper
          ];
          patches = [
            ./patches/cooja.patch
            ./patches/mspsim-build.patch
          ];
          prePatch = ''
            cp -r ${mspsim}/* tools/mspsim
          '';
          buildPhase = ''
            cd tools/cooja
            ant jar
          '';
          # TODO: this copies way more than we need, we really don't need app/src
          installPhase = ''
            mkdir -p $out/lib
            cp -r dist/* $out/lib/
            for app in apps/*; do
              dest="$out/lib/tools/cooja/apps"
              mkdir -p "$dest"
              cp -r "$app" "$dest/"
            done

            makeWrapper ${pkgs.jdk8}/bin/java $out/bin/cooja \
              --add-flags "-jar $out/lib/cooja.jar" \
              --add-flags "-contiki=$out/lib"
          '';
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            ccache
            msp430-gcc
            msp430-binutils
            msp430-binutils-symlinked
            # msp430-gdb
            rlwrap
            msp430-mcu
            msp430-libc
            cooja
            contiki-os-source
          ];
          shellHook = ''
            export CONTIKI=${contiki-os-source}
          '';
        };
      }
    );
}
