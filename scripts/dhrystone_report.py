from __future__ import annotations

import argparse
import re
from pathlib import Path


TOTAL_CYCLES_PATTERN = re.compile(r"^DHRYSTONE_TOTAL_CYCLES:\s*(\d+)\s*$", re.MULTILINE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Extract Dhrystone benchmark metrics from UART output.")
    parser.add_argument("--uart-log", type=Path, required=True, help="Path to the UART transcript produced by the simulator.")
    parser.add_argument("--iterations", type=int, required=True, help="Number of Dhrystone iterations compiled into the benchmark.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    text = args.uart_log.read_text(encoding="utf-8")
    match = TOTAL_CYCLES_PATTERN.search(text)
    if match is None:
        raise SystemExit(f"Could not find DHRYSTONE_TOTAL_CYCLES in {args.uart_log}")

    total_cycles = int(match.group(1))
    cycles_per_iteration = total_cycles / args.iterations
    dmips_per_mhz = 1_000_000 / (1757 * cycles_per_iteration)

    print(f"UART log: {args.uart_log}")
    print(f"Total cycles: {total_cycles}")
    print(f"Iterations: {args.iterations}")
    print(f"Cycles per iteration: {cycles_per_iteration:.3f}")
    print(f"DMIPS/MHz: {dmips_per_mhz:.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
