# cooja-contiki-os
Nix wrapper for [Contiki](https://github.com/contiki-os/contiki) and Cooja.
Very inspired by [bjoluc/docker-contiki](https://github.com/bjoluc/docker-contiki).
The [cooja.patch](/nix/patches/cooja.patch) file was also copied from there.

## Usage
Nix flake support is necessary.
Note that `nix develop` might take a while on the first run, the GNU mirrors are quite slow.
```sh
cd nix
nix develop # builds the toolchain
cd ../hello-world # or wherever you have your code
make -j`nproc` # should yield a *.sky file
cooja # starts the simulator
```
