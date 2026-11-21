"""
gen_test.py
Calls riscv-dv (pyflow mode, inside WSL) to generate a random RV32I
assembly test and returns the path to the generated .S file.

Usage:
    python3 gen_test.py --test riscv_arithmetic_basic_test --outdir <dir>

Available test names (RV32I relevant):
    riscv_arithmetic_basic_test   -- ADD/SUB/AND/OR/XOR/SLL/SRL/SRA + immediates
    riscv_rand_instr_test         -- fully random mix of all instructions
    riscv_jump_stress_test        -- heavy JAL/JALR/branch sequences
    riscv_loop_test               -- loops with branches
"""
from __future__ import annotations
import argparse, subprocess, sys, os, platform
from pathlib import Path

# Paths inside WSL
RISCV_DV_DIR = "~/riscv-dv"
VENV_PYTHON  = "~/riscv-dv/.venv/bin/python3"

def to_wsl(win_path: Path) -> str:
    """Return a WSL-usable path. When already on Linux the path is unchanged."""
    if platform.system() == "Linux":
        return str(win_path)
    r = subprocess.run(["wsl", "wslpath", str(win_path)],
                       capture_output=True, text=True)
    return r.stdout.strip()

def gen_test(test_name: str, outdir: Path, iterations: int = 1) -> list[Path]:
    outdir.mkdir(parents=True, exist_ok=True)
    wsl_outdir = to_wsl(outdir.resolve())

    print(f"[riscv-dv] generating {iterations}x {test_name} ...")
    inner = (
        f"export PATH={RISCV_DV_DIR}/.venv/bin:$PATH && "
        f"cd {RISCV_DV_DIR} && "
        f"python3 run.py "
        f"--test {test_name} "
        f"--isa rv32i "
        f"--mabi ilp32 "
        f"--simulator pyflow "
        f"--target rv32i "
        f"--output {wsl_outdir} "
        f"--iterations {iterations}"
    )
    # When running from Windows use `wsl bash -c`; inside WSL use bash directly.
    if platform.system() == "Linux":
        cmd = ["bash", "-c", inner]
    else:
        cmd = ["wsl", "bash", "-c", inner]
    # Stream output directly to terminal — capturing causes pipe-buffer deadlock.
    # riscv-dv exits non-zero when RISCV_GCC is unset (compilation step fails),
    # but the .S files are already written before that — check for them directly.
    subprocess.run(cmd)

    # riscv-dv writes .S files to <outdir>/asm_test/
    asm_dir = outdir / "asm_test"
    asm_files = sorted(asm_dir.glob("*.S"))
    if not asm_files:
        print(f"[riscv-dv] ERROR: no .S files found in {asm_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"[riscv-dv] generated: {[f.name for f in asm_files]}")
    return asm_files

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--test",       default="riscv_arithmetic_basic_test")
    p.add_argument("--outdir",     type=Path, default=Path("out/gen"))
    p.add_argument("--iterations", type=int,  default=1)
    args = p.parse_args()
    gen_test(args.test, args.outdir, args.iterations)
