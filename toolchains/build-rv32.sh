#!/bin/bash
set -euo pipefail

# Build a native macOS compiler whose real target is riscv32-unknown-elf.
# Sources are extracted into a temporary, case-sensitive APFS volume.
project_dir=$(cd "$(dirname "$0")/.." && pwd)
build_root=/private/tmp/fpga-rv32-build
source_root="$build_root/riscv-gnu-toolchain-2026.08.27"
install_dir="$project_dir/toolchains/riscv32-unknown-elf"
export LC_ALL=C
export PATH="/opt/homebrew/opt/gawk/libexec/gnubin:/opt/homebrew/opt/gnu-sed/libexec/gnubin:/opt/homebrew/opt/make/libexec/gnubin:/opt/homebrew/opt/texinfo/bin:/opt/homebrew/bin:$PATH"
export CPPFLAGS="-I/opt/homebrew/opt/gmp/include -I/opt/homebrew/opt/mpfr/include -I/opt/homebrew/opt/libmpc/include"
export LDFLAGS="-L/opt/homebrew/opt/gmp/lib -L/opt/homebrew/opt/mpfr/lib -L/opt/homebrew/opt/libmpc/lib"
export GCC_EXTRA_CONFIGURE_FLAGS="--with-gmp=/opt/homebrew/opt/gmp --with-mpfr=/opt/homebrew/opt/mpfr --with-mpc=/opt/homebrew/opt/libmpc --disable-bootstrap --disable-werror"
export BINUTILS_TARGET_FLAGS_EXTRA="--disable-nls --disable-werror"

mkdir -p "$build_root/build" "$install_dir"
cd "$build_root/build"
if [ ! -f Makefile ]; then
    "$source_root/configure" \
        --prefix="$install_dir" \
        --with-arch=rv32i --with-abi=ilp32 \
        --disable-multilib --disable-gdb --with-languages=c \
        --with-gcc-src="$build_root/gcc-15.2.0" \
        --with-binutils-src="$build_root/binutils-2.45" \
        --with-newlib-src="$build_root/newlib-4.5.0.20241231"
fi
exec /opt/homebrew/bin/gmake -j6 "${1:-newlib}"
