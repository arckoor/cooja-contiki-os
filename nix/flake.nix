{
  description = "Cooja with msp430-gcc";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    lib-nixpkgs.url = "github:NixOS/nixpkgs/5ed627539ac84809c78b2dd6d26a5cebeb5ae269";
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
    lib-nixpkgs,
    flake-utils,
    nixpkgs-python,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };
        lib-pkgs = import lib-nixpkgs {
          inherit system;
        };

        gcc4-pkgs = import (fetchTarball {
          url = "https://github.com/NixOS/nixpkgs/archive/0c66dbaee6647abfb4d2774588a0cf0ad8d4f02b.tar.gz";
          sha256 = "sha256:040m9qprszi9x9zbkdjqf35pp7nx7jpama9kicv5ix4pxiiw5ap4";
        }) {inherit system;};

        mkScript = name: text: (pkgs.writeShellScriptBin name text);

        shellScripts = [
          (mkScript "init" ''
            cd ../
            git clone https://github.com/contiki-os/contiki.git --recurse-submodules
            cd contiki/tools/cooja
            ant compile
          '')

          (mkScript "run" ''
            cd ../contiki/tools/cooja
            ant run
          '')
        ];

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
          pname = "msp430-bintuils-sl";
          version = "2.21.1";
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

        msp430-gcc-unwrapped = gcc4-pkgs.stdenv.mkDerivation rec {
          version = "4.6.3";
          name = "msp430-gcc-unwrapped-${version}";
          src = pkgs.fetchzip {
            url = "https://ftp.gnu.org/pub/gnu/gcc/gcc-4.6.3/gcc-4.6.3.tar.bz2";
            hash = "sha256-RIvXckvIyuaNB1i+ZOPhcWAU7YKgYBj2meHEBkjT/O8=";
          };
          patches = [
            "${msp430-patches}/msp430-gcc-4.6.3-20120406.patch"
          ];
          nativeBuildInputs = with gcc4-pkgs; [
            gmp
            mpfr
            mpc
            flex
            bison
            texinfo
            gcc44
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
            "--enable-languages=c,c++"
            # "--with-gmp=${gcc4-pkgs.gmp}"
            # "--with-mpfr=${gcc4-pkgs.mpfr}"
            # "--with-mpc=${gcc4-pkgs.mpc}"
          ];
          postInstall = ''
            # mv $out/bin/msp430-gcc $out/bin/msp430-gcc-unwrapped
            # makeWrapper $out/bin/msp430-gcc-unwrapped $out/bin/msp430-gcc \
            #   --set LC_ALL C
          '';
          enableParallelBuilding = true;
        };

        msp430-mcu = pkgs.stdenvNoCC.mkDerivation rec {
          pname = "msp430-mcu";
          version = "20120406";
          src = pkgs.fetchzip {
            url = "https://sourceforge.net/projects/mspgcc/files/msp430mcu/msp430mcu-${version}.zip";
            hash = "sha256-da7RmEjbRIWw+nYg2k1aobspex/GpYGJS1bwm/7t4Ak=";
          };
          installPhase = ''
            mkdir -p $out/upstream $out/lib $out/analysis
            cp upstream/*h $out/upstream
            cp include/*.h $out/lib
            cp -r analysis/* $out/analysis
          '';
        };

        msp430-libc = gcc4-pkgs.stdenv.mkDerivation rec {
          version = "20120224";
          name = "msp430-libc-${version}";
          src = pkgs.fetchzip {
            url = "https://sourceforge.net/projects/mspgcc/files/msp430-libc/msp430-libc-${version}.zip";
            hash = "sha256-NTLQpFgI1rFSQule/lBLf+ftQ5rsx8HiakQcZuaRvLI=";
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

        msp430-lib = pkgs.stdenvNoCC.mkDerivation {
          pname = "msp430-libs";
          version = "1.0";
          nativeBuildInputs = [
            msp430-libc
            msp430-mcu
          ];
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/include $out/lib
            cp ${msp430-mcu}/upstream/* $out/include
            cp ${msp430-mcu}/lib/* $out/include
            cp -r ${msp430-mcu}/analysis/ldscripts  $out/lib
            cp ${msp430-mcu}/analysis/msp430mcu.spec  $out/lib

            cp -r ${msp430-libc}/msp430/lib/* $out/lib
            cp -r ${msp430-libc}/msp430/include/* $out/include
          '';
        };

        msp430-gcc = pkgs.stdenvNoCC.mkDerivation {
          pname = "msp430-gcc";
          version = "1.0";
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
          packages = with pkgs;
            [
              ccache
              msp430-gcc
              msp430-binutils
              msp430-binutils-symlinked
              msp430-gdb
              rlwrap
              cooja
              msp430-mcu
              msp430-libc
            ]
            ++ shellScripts;
          shellHook = ''
          '';
        };
      }
    );
}
