"""
gen_all.py
Reads verif/tests.yaml and runs the full generation pipeline for each test:
  riscv-dv  ->  compile (.S -> ELF + hex)  ->  Spike (ELF -> spike_parsed.json)

Existing test folders are detected and skipped so re-running is safe.
New tests are numbered starting from the next available index.

Usage (from the RISCV/ root, inside WSL):
    python3 verif/scripts/gen_all.py
    python3 verif/scripts/gen_all.py --plan verif/tests.yaml
"""
from __future__ import annotations
import argparse, sys
from pathlib import Path

SCRIPTS  = Path(__file__).parent
ROOT     = SCRIPTS.parents[1]
LOGS_DIR = ROOT / "verif" / "logs"

sys.path.insert(0, str(SCRIPTS))
from gen_test      import gen_test
from compile_test  import compile_test
from run_spike     import run_spike


def next_index(test_name: str) -> int:
    """Return the first unused integer suffix for <test_name>_N folders."""
    existing = sorted(LOGS_DIR.glob(f"{test_name}_*"))
    indices  = []
    for d in existing:
        suffix = d.name[len(test_name) + 1:]
        if suffix.isdigit():
            indices.append(int(suffix))
    return max(indices) + 1 if indices else 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--plan", type=Path,
                   default=ROOT / "verif" / "tests.yaml")
    args = p.parse_args()

    try:
        import yaml
    except ImportError:
        # Minimal YAML parser for the simple list format used here
        import types
        def _load_yaml(text):
            # Only handles the specific format in tests.yaml
            tests = []
            current = None
            for line in text.splitlines():
                stripped = line.strip()
                if stripped.startswith("- name:"):
                    current = {"name": stripped.split(":", 1)[1].strip(), "iterations": 1}
                    tests.append(current)
                elif stripped.startswith("iterations:") and current:
                    current["iterations"] = int(stripped.split(":", 1)[1].strip())
            return {"tests": tests}
        yaml = types.SimpleNamespace(safe_load=lambda f: _load_yaml(f.read()))

    with open(args.plan) as f:
        plan = yaml.safe_load(f)

    total_pass = 0
    total_fail = 0

    for entry in plan["tests"]:
        test_name  = entry["name"]
        iterations = entry.get("iterations", 1)
        start_idx  = next_index(test_name)

        print(f"\n{'='*60}")
        print(f"  Generating {iterations} x {test_name}  (starting at index {start_idx})")
        print(f"{'='*60}")

        # 1. Generate .S files via riscv-dv
        gen_outdir = LOGS_DIR / f"_gen_{test_name}"
        asm_files  = gen_test(test_name, gen_outdir, iterations)

        for i, asm in enumerate(asm_files):
            label  = f"{test_name}_{start_idx + i}"
            outdir = LOGS_DIR / label
            outdir.mkdir(parents=True, exist_ok=True)

            print(f"\n--- {label} ---")

            # 2. Compile .S -> ELF + instr_mem.hex
            elf, hexf = compile_test(asm, outdir)

            # 3. Run Spike -> spike_parsed.json
            run_spike(elf, outdir)

            total_pass += 1

        # Clean up temporary gen directory
        import shutil
        shutil.rmtree(gen_outdir, ignore_errors=True)

    print(f"\n{'='*60}")
    print(f"  Generated {total_pass} test(s) into {LOGS_DIR}")
    print(f"  Run `make regress` to simulate and compare.")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
