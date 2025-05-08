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

        msp430-binutils = pkgs.stdenv.mkDerivation {
          pname = "msp430-binutils";
          version = "2.21.1a";
          src = pkgs.fetchurl {
            url = "https://ftp.gnu.org/pub/gnu/binutils/binutils-2.21.1a.tar.bz2";
            hash = "sha256-zez6afAqp7BfvN9njjMTcVHzYTE7Lz5Iq6kl9k6r9lQ=";
          };
          patches = [
            "${msp430-patches}/msp430-binutils-2.21.1a-20120406.patch"
          ];
          nativeBuildInputs = with pkgs; [
            bison
            flex
            gmp
            libmpc
            mpfr
            texinfo
          ];
          makeFlags = ["MAKEINFO=true"];
          configureFlags = [
            "--target=msp430"
            "--disable-werror"
          ];
          enableParallelBuilding = true;
        };

        msp430-binutils-symlinked = pkgs.stdenvNoCC.mkDerivation {
          pname = "msp430-bintuils-symlinked";
          inherit (msp430-binutils) version;
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

        msp430-gcc-unwrapped = pkgs.stdenv.mkDerivation {
          pname = "msp430-gcc-unwrapped";
          version = "4.6.3";
          src = pkgs.fetchurl {
            url = "https://ftp.gnu.org/pub/gnu/gcc/gcc-4.6.3/gcc-4.6.3.tar.bz2";
            hash = "sha256-6PWFPU7sL166+Kcq5NU8Q2qs+YFTskmfhjW0jEcYoJM=";
          };
          patches = [
            "${msp430-patches}/msp430-gcc-4.6.3-20120406.patch"
          ];
          nativeBuildInputs = with pkgs; [
            bison
            flex
            gmp
            libmpc
            mpfr
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
          ];
          enableParallelBuilding = true;
          NIX_CFLAGS_COMPILE = "-Wno-error=format-security";
        };

        msp430-mcu = pkgs.stdenvNoCC.mkDerivation rec {
          pname = "msp430-mcu";
          version = "20120406";
          src = pkgs.fetchzip {
            url = "https://sourceforge.net/projects/mspgcc/files/msp430mcu/msp430mcu-${version}.tar.bz2";
            hash = "sha256-da7RmEjbRIWw+nYg2k1aobspex/GpYGJS1bwm/7t4Ak=";
          };
          installPhase = ''
            mkdir -p $out/include $out/lib
            cp upstream/*h $out/include
            cp include/*.h $out/include
            cp analysis/msp430.h $out/include

            cp analysis/msp430mcu.spec $out/lib
            cp -r analysis/ldscripts $out/lib
          '';
        };

        msp430-libc = pkgs.stdenv.mkDerivation rec {
          pname = "msp430-libc";
          version = "20120224";
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
          pname = "msp430-lib";
          version = pkgs.lib.concatStrings [msp430-mcu.version "-" msp430-libc.version];
          nativeBuildInputs = [
            msp430-libc
            msp430-mcu
          ];
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/include $out/lib
            cp -r ${msp430-mcu}/* $out/
            cp -r ${msp430-libc}/msp430/* $out/
          '';
        };

        msp430-gcc = pkgs.stdenv.mkDerivation {
          pname = "msp430-gcc";
          inherit (msp430-gcc-unwrapped) version;
          nativeBuildInputs = with pkgs; [
            msp430-gcc-unwrapped
            msp430-lib
            makeWrapper
          ];
          dontUnpack = true;
          # TODO would be nice to not have to hardcode the specific ldscript
          installPhase = ''
            mkdir -p $out/bin $out/include $out/lib/gcc $out/libexec

            cp -r ${msp430-gcc-unwrapped}/lib/* $out/lib/
            cp -r ${msp430-gcc-unwrapped}/libexec/* $out/libexec/
            cp -r ${msp430-lib}/* $out
            cp ${msp430-lib}/lib/msp430mcu.spec $out/lib/gcc

            makeWrapper ${msp430-gcc-unwrapped}/bin/msp430-gcc $out/bin/msp430-gcc \
              --add-flags "-isystem $out/include -L$out/lib -L$out/lib/ldscripts/msp430f1611" \
              --set GCC_EXEC_PREFIX $out/lib/gcc/ \
              --set LC_ALL C
          '';
        };

        contiki-os-source = pkgs.stdenv.mkDerivation rec {
          pname = "contiki-os-source";
          version = "3.0";
          src = pkgs.fetchFromGitHub {
            owner = "contiki-os";
            repo = "contiki";
            rev = version;
            hash = "sha256-WMkdS9GSqKZ3/6/tEbnzD/B8q4NATLwG9DIdz0ePfgQ=";
          };
          mspsim = pkgs.fetchFromGitHub {
            owner = "contiki-os";
            repo = "mspsim";
            rev = "58f187351f3417814aa2d0d92af9e2bb768d92ee";
            hash = "sha256-KHXOoE/j08+S4PCgV/Vgp9CcLeNlilMVklR26o9fB/c=";
          };
          patches = [
            ./patches/contiki.patch
            ./patches/cooja.patch
          ];
          prePatch = ''
            cp -r --no-preserve=mode ${mspsim}/* tools/mspsim
          '';
          installPhase = ''
            mkdir -p $out
            cp -r * $out
          '';
        };

        cooja = pkgs.stdenv.mkDerivation {
          pname = "cooja";
          inherit (contiki-os-source) version;
          dontUnpack = true;
          nativeBuildInputs = with pkgs; [
            ant
            jdk8
            makeWrapper
            contiki-os-source
          ];
          configurePhase = ''
            cp -r --no-preserve=mode ${contiki-os-source}/* .
          '';
          buildPhase = ''
            cd tools/cooja
            ant jar
          '';
          # TODO this copies way more than we need, we really don't need app/src
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
            cooja
            contiki-os-source
            msp430-binutils
            msp430-binutils-symlinked
            msp430-gcc
          ];
          shellHook = ''
            export CONTIKI=${contiki-os-source}
          '';
        };
      }
    );
}
