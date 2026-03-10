#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def discover_elfs(elf_root: Path) -> list[Path]:
    return sorted(elf_root.rglob("*.elf"))


def tail_text(text: str, limit: int = 80) -> list[str]:
    lines = text.splitlines()
    if len(lines) <= limit:
        return lines
    return lines[-limit:]


def extract_summary(uart_text: str, stdout: str, stderr: str) -> str | None:
    combined = "\n".join(part for part in [uart_text, stdout, stderr] if part)
    for line in combined.splitlines():
        if "RVCP-SUMMARY:" in line:
            return line.strip()
    return None


def extract_debug(uart_text: str, stdout: str, stderr: str) -> list[str]:
    combined = "\n".join(part for part in [uart_text, stdout, stderr] if part)
    out: list[str] = []
    for line in combined.splitlines():
        low = line.lower()
        if any(
            token in low
            for token in [
                "failing pc",
                "failing instruction",
                "which register mismatched",
                "expected value",
                "actual value",
            ]
        ):
            out.append(line.strip())
    return out


def sanitize_name(path: Path) -> str:
    return "_".join(path.parts)


def run_one(repo_root: Path, elf_rel: Path, elf: Path, max_cycles: int, log_dir: Path) -> dict[str, object]:
    slug = sanitize_name(elf_rel)
    stdout_path = log_dir / f"{slug}.stdout.log"
    stderr_path = log_dir / f"{slug}.stderr.log"
    uart_path = log_dir / f"{slug}.uart.log"
    cmd = [
        "make",
        "sim-elf",
        f"PROGRAM_ELF={elf}",
        f"MAX_CYCLES={max_cycles}",
    ]
    env = dict(os.environ)
    env["UART_LOG_PATH"] = str(uart_path)
    proc = subprocess.run(cmd, cwd=repo_root,
                          capture_output=True, text=True, env=env)

    stdout_path.write_text(proc.stdout, encoding="utf-8")
    stderr_path.write_text(proc.stderr, encoding="utf-8")
    uart_text = uart_path.read_text(
        encoding="utf-8") if uart_path.exists() else ""

    reason = "failed"
    if "Timeout: no tohost write" in proc.stdout or "Timeout: no tohost write" in proc.stderr:
        reason = "timeout"

    result = {
        "elf": str(elf),
        "ok": proc.returncode == 0,
        "reason": "pass" if proc.returncode == 0 else reason,
        "returncode": proc.returncode,
        "summary": extract_summary(uart_text, proc.stdout, proc.stderr),
        "debug": extract_debug(uart_text, proc.stdout, proc.stderr),
        "stdout_log": str(stdout_path),
        "stderr_log": str(stderr_path),
        "uart_log": str(uart_path),
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run ACT4-generated ELFs on cocotb DUT")
    parser.add_argument("--elf-root", required=True, type=Path)
    parser.add_argument("--max-cycles", type=int, default=200000)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    elf_root = args.elf_root.resolve()
    elfs = discover_elfs(elf_root)

    if not elfs:
        print(f"No ELFs found under {args.elf_root}")
        return 2

    results = []
    passed = 0
    log_dir = args.report.parent / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    for idx, elf in enumerate(elfs, start=1):
        result = run_one(
            repo_root,
            elf.relative_to(elf_root),
            elf.resolve(),
            args.max_cycles,
            log_dir,
        )
        status = "PASS" if result["ok"] else "FAIL"
        print(f"[{idx}/{len(elfs)}] {status} {elf.stem}")
        if result["ok"]:
            passed += 1
        results.append(result)

    summary = {
        "total": len(elfs),
        "passed": passed,
        "failed": len(elfs) - passed,
        "log_dir": str(log_dir),
        "results": results,
    }

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(
        summary, indent=2) + "\n", encoding="utf-8")

    print(f"Summary: {passed}/{len(elfs)} passed")
    print(f"Report: {args.report}")

    return 0 if passed == len(elfs) else 1


if __name__ == "__main__":
    sys.exit(main())
