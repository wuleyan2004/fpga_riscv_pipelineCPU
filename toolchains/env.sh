# Bash / zsh: source this file to load the project compiler.
if [ -n "${BASH_VERSION:-}" ]; then
    _fpga_env_file="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
    _fpga_env_file="$0"
else
    echo "Please source env.sh from Bash or zsh." >&2
    return 1
fi
_fpga_toolchain_dir=$(cd "$(dirname "$_fpga_env_file")" && pwd) || return 1
export PATH="$_fpga_toolchain_dir/riscv32-unknown-elf/bin:$PATH"
unset _fpga_env_file _fpga_toolchain_dir
