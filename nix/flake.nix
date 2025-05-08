{
  description = "Cooja with msp430-gcc";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs = {
    nixpkgs,
    flake-utils,
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
          version = "20120406";
          src = pkgs.fetchzip {
            url = "https://sourceforge.net/projects/mspgcc/files/mspgcc/mspgcc-${version}.zip";
            hash = "sha256-gVIURNjW4yq6ki/2x8uvty2OwlJ5Kv4FDcqBqdiPb+0=";
          };
          installPhase = ''
            mkdir -p $out
            cp *.patch $out
          '';
        };

        msp430-binutils = gcc4-pkgs.stdenv.mkDerivation rec {
          version = "2.21.1";
          name = "msp430-binutils-${version}";
          src = pkgs.fetchurl {
            url = "https://ftp.gnu.org/pub/gnu/binutils/binutils-2.21.1a.tar.bz2";
            hash = "sha256-zez6afAqp7BfvN9njjMTcVHzYTE7Lz5Iq6kl9k6r9lQ=";
          };
          patches = [
            "${msp430-patches}/msp430-binutils-2.21.1a-20120406.patch"
          ];
          nativeBuildInputs = with gcc4-pkgs; [
            gmp
            mpfr
            mpc
            flex
            bison
            texinfo
          ];
          makeFlags = ["MAKEINFO=true"];
          configureFlags = [
            "--target=msp430"
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

        # msp430-gcc SETUP ----------------------------------------------------------------------

        msp430-mcu = pkgs.stdenv.mkDerivation rec {
          pname = "msp430-mcu";
          version = "20120406";
          src = pkgs.fetchurl {
            url = "https://sourceforge.net/projects/mspgcc/files/msp430mcu/msp430mcu-${version}.tar.bz2";
            hash = "sha256-BjcBTo5Ql0bD9t+OHWW3hncNFis6C4ZUi992rDECyW4=";
          };
          installPhase = ''

            PREFIX=$out
            MSP430MCU_ROOT=./
            UPSTREAM=$MSP430MCU_ROOT/upstream
            ANALYSIS=$MSP430MCU_ROOT/analysis
            SCRIPTS=$MSP430MCU_ROOT/scripts
            VERSION=`cat $MSP430MCU_ROOT/.version`
            UPSTREAM_VERSION=`cat $MSP430MCU_ROOT/upstream/.version`

            BINPATH=$PREFIX/bin
            INCPATH=$PREFIX/msp430/include
            LIBPATH=$PREFIX/msp430/lib

            mkdir -p $INCPATH $LIBPATH

            # Upstream headers
            install -p -m 0644 $UPSTREAM/*.h $INCPATH

            # Local override headers
            install -p -m 0644 $MSP430MCU_ROOT/include/*.h $INCPATH

            # Override msp430.h to accommodate legacy MSPGCC MCU identifiers
            install -p -m 0644 $ANALYSIS/msp430.h $INCPATH

            # MCU-specific data for GCC driver program
            install -p -m 0644 $ANALYSIS/msp430mcu.spec $LIBPATH

            # Install MCU-specific memory and periph maps
            cp -pr $ANALYSIS/ldscripts $LIBPATH
            chmod -R og+rX $LIBPATH/ldscripts

            # Install utility that tells where everything got installed
            #cat bin/msp430mcu-config.in \
            #| sed \
            #    -e 's!@PREFIX@!'"$PREFIX"'!g' \
            #    -e 's!@SCRIPTPATH@!'"$LIBPATH/ldscripts"'!g' \
            #    -e 's!@INCPATH@!'"$INCPATH"'!g' \
            #    -e 's!@VERSION@!'"$VERSION"'!g' \
            #    -e 's!@UPSTREAM_VERSION@!'"$UPSTREAM_VERSION"'!g' \
            #> $BINPATH/msp430mcu-config \
            #&& chmod 0755 $BINPATH/msp430mcu-config
          '';
        };

        msp430-gcc-unwrapped = pkgs.stdenv.mkDerivation rec {
          version = "4.6.3";
          name = "msp430-gcc-unwrapped-${version}";
          src = pkgs.fetchurl {
            url = "https://ftp.gnu.org/pub/gnu/gcc/gcc-4.6.3/gcc-4.6.3.tar.bz2";
            hash = "sha256-6PWFPU7sL166+Kcq5NU8Q2qs+YFTskmfhjW0jEcYoJM=";
          };
          patches = [
            "${msp430-patches}/msp430-gcc-4.6.3-20120406.patch"
            ./patches/gcc.patch
          ];
          nativeBuildInputs = with pkgs; [
            gmp
            mpfr
            libmpc

            flex
            bison
            texinfo
            msp430-binutils
          ];
          hardeningDisable = ["all"];
          makeFlags = ["MAKEINFO=true" "CFLAGS=\"-g\""];
          preConfigure = ''
            mkdir build
            cd build
          '';
          configureScript = "../configure";
          configureFlags = [
            "--target=msp430"
            "--enable-languages=c"
            "--disable-nls"
            "--disable-libssp"
          ];
          enableParallelBuilding = true;
          NIX_CFLAGS_COMPILE = "-Wno-error=format-security";
        };


        msp430-libc = pkgs.stdenv.mkDerivation rec {
          version = "20120224";
          name = "msp430-libc-${version}";
          src = pkgs.fetchurl {
            url = "https://sourceforge.net/projects/mspgcc/files/msp430-libc/msp430-libc-${version}.tar.bz2";
            hash = "sha256-tnoziBqmtFbFyZ3qXqZViSRV/eExfVvagY6cbuNKP4I=";
          };
          nativeBuildInputs = [
            msp430-binutils
            msp430-binutils-symlinked
            msp430-gcc-unwrapped
          ];
          makeFlags = ["MAKEINFO=true"];
          buildPhase = ''
            cd src
            make
          '';
          enableParallelBuilding = true;
        };

        msp430-lib = pkgs.stdenv.mkDerivation {
          pname = "msp430-libs";
          version = "1.0";
          nativeBuildInputs = [
            msp430-libc
            msp430-mcu
          ];
          dontUnpack = true;
          installPhase = ''

            mkdir -p $out/include
            mkdir -p $out/lib

            cp -r ${msp430-mcu}/msp430/* $out/
            cp -r ${msp430-libc}/msp430/* $out/

          '';
        };

        msp430-gcc = pkgs.stdenv.mkDerivation {
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
            mkdir -p $out/include
            mkdir -p $out/lib/gcc
            mkdir -p $out/libexec/

            cp -r ${msp430-gcc-unwrapped}/lib/* $out/lib/
            cp -r ${msp430-gcc-unwrapped}/libexec/* $out/libexec/

            cp -r ${msp430-lib}/* $out

            cp ${msp430-lib}/lib/msp430mcu.spec $out/lib/gcc

            makeWrapper ${msp430-gcc-unwrapped}/bin/msp430-gcc $out/bin/msp430-gcc \
              --add-flags "-I$out/include -L$out/lib -L$out/lib/ldscripts/msp430f1611" \
              --set LC_ALL C \
              --set GCC_EXEC_PREFIX $out/lib/gcc/
          ''; 
        };

        # msp430-gdb SETUP ----------------------------------------------------------------------

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
            rev = "3.0";
            hash = "sha256-rMSDFbYxtXhCsWGXphjb1qoI0HRU5wet9QUQV9NCySI=";
          };
          patches = [
            ./patches/cooja.patch
          ];
          installPhase = ''
            mkdir -p $out
            cp -r * $out
          '';
        };

        mspsim-source = pkgs.stdenv.mkDerivation {
          name = "mspsim-source";
          src = pkgs.fetchFromGitHub {
            owner = "contiki-os";
            repo = "mspsim";
            rev = "47ae45cb0f36337115e32adb2a5ba0bf6e1e4437";
            hash = "sha256-Notvul48WXj6JxciFmSUVHM2rguVG2t2HO1t8PBipiI=";
          };
          prePatch = ''
            ls -lafh
          '';
          phases = ["unpackPhase" "prePatch" "patchPhase" "installPhase" ];
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
          nativeBuildInputs = with pkgs; [
            jdk8
            ant
            makeWrapper
            mspsim-source
          ];
          prePatch = ''
            cp -r ${mspsim-source}/* tools/mspsim
          '';
          patches = [
            ./patches/cooja.patch
            ./patches/mspsim-build.patch
          ];
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
            msp430-gdb
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
