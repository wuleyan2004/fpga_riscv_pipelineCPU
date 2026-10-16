#!/usr/bin/env python3
"""Run short real-RTL CoreMark tests; these are CRC tests, not reported scores."""
import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--run", choices=("performance", "validation"), default="performance")
parser.add_argument("--package", type=Path, help="Package containing a one-iteration embedded image")
parser.add_argument("--iterations", type=int, choices=(0, 1), default=1)
parser.add_argument("--profile", action="store_true", help="Test diagnostic CoreMark image")
args = parser.parse_args()
OUT = ROOT / "build" / (f"coremark-{args.run}-{args.iterations}"
                        + ("-profile" if args.profile else ""))
metadata = json.loads((OUT / "metadata.json").read_text())
symbols = metadata["symbols"]
expected = {"performance": ("e9f5", "e714", "1fd7", "8e3a"),
            "validation": ("18f2", "e3c1", "0747", "8d84")}[args.run]
boots = 1 if args.iterations == 0 else 2
params = {"FILE_MODE": 0 if args.package else 1, "BOOTS": boots,
          "CALIBRATION_ONLY": int(args.iterations == 0), "ITERATE_PC": symbols["iterate"],
          **{name: offset for name, offset in zip(("LIST_OFFSET", "MATRIX_OFFSET", "STATE_OFFSET"), metadata["crc_offsets"])},
          **{name: int(crc, 16) for name, crc in zip(("EXPECT_LIST", "EXPECT_MATRIX", "EXPECT_STATE"), expected[1:])},
          "HALT_PC": symbols["__boot_halt"], "BSS_END": symbols["__bss_end"],
          "SNAPSHOT_START": symbols["__data_load_start"], "SNAPSHOT_END": symbols["__data_load_end"],
          "START_CYCLES_ADDR": symbols["measured_start_cycles"],
          "STOP_CYCLES_ADDR": symbols["measured_stop_cycles"]}
if args.package:
    sources = [args.package / line for line in (args.package / "sources.f").read_text().splitlines() if line]
    tag = "package"
else:
    sources = [ROOT / line for line in (ROOT / "board_sources.f").read_text().splitlines() if line]
    tag = "file"
exe = OUT / (tag + ".vvp")
command = ["iverilog", "-g2012", "-s", "tb_coremark", "-o", str(exe),
           *[f"-Ptb_coremark.{k}={v}" for k, v in params.items()],
           *map(str, sources), str(ROOT / "tests/tb_coremark.sv")]
subprocess.run(command, cwd=OUT, check=True, capture_output=True, text=True, timeout=60)
with (OUT / (tag + ".simulation.log")).open("w") as log:
    result = subprocess.run(["vvp", str(exe)], cwd=OUT, stdout=log, stderr=subprocess.STDOUT, timeout=300)
simulation = (OUT / (tag + ".simulation.log")).read_text()
print(simulation, end="", flush=True)
if result.returncode or "PASS coremark_board" not in simulation:
    raise SystemExit("FAIL CoreMark RTL execution")
serial = (OUT / "uart.txt").read_text()
blocks = serial.split("--BOOT-END--")
for block in blocks[:boots]:
    if args.iterations == 0:
        if "CoreMark RV32I start; clock=27000000 Hz" not in block:
            raise SystemExit("FAIL automatic-run UART startup banner")
        continue
    for field, crc in zip(("seedcrc", "crclist", "crcmatrix", "crcstate"), expected):
        match = re.search(rf"{field}\s*:\s*0x([0-9a-fA-F]+)", block)
        if not match or match[1].lower() != crc:
            raise SystemExit(f"FAIL {field}: expected {crc}\n{block}")
    ticks = int(re.search(r"Total ticks\s*:\s*(\d+)", block)[1])
    seconds = float(re.search(r"Total time \(secs\):\s*([\d.]+)", block)[1])
    if ticks <= 0 or abs(seconds - ticks * 1024 / 27000000) > 0.000002:
        raise SystemExit("FAIL cycle/time conversion")
    errors = [line for line in block.splitlines() if "ERROR!" in line]
    if errors != ["ERROR! Must execute for at least 10 secs for a valid result!"]:
        raise SystemExit(f"FAIL unexpected short-run errors: {errors}")
    if "Iterations       : 1" not in block:
        raise SystemExit("FAIL iteration count")
    if args.profile:
        values = {}
        for label in ("Profile cycles", "Retired instructions", "Memory wait cycles",
                      "RAW wait cycles", "Branch instructions", "Taken branches",
                      "Branch bubble cycles", "Jump bubble cycles"):
            match = re.search(rf"{label}\s*:\s*(\d+)", block)
            if not match:
                raise SystemExit(f"FAIL missing profile field: {label}")
            values[label] = int(match[1])
        if not (values["Profile cycles"] > values["Retired instructions"] > 0
                and values["Memory wait cycles"] > 0
                and values["Taken branches"] > 0
                and values["Branch bubble cycles"] == values["Taken branches"]
                and values["Branch instructions"] >= values["Taken branches"]):
            raise SystemExit(f"FAIL inconsistent profile counters: {values}")
summary = {"passed": True, "run": args.run, "boots": boots, "expected_crc": expected,
           "calibration_only": args.iterations == 0,
           "uart_bit_decode": True, "formal_score": False, "reason": "one iteration, below 10 seconds"}
(OUT / (tag + ".test.json")).write_text(json.dumps(summary, indent=2))
(OUT / (tag + ".uart.txt")).write_text(serial)
print(f"PASS {args.run} official CRCs={expected}; short run is not a formal score", flush=True)
