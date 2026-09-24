#!/usr/bin/env python3
"""Run the headless test suite and report one table of results.

Every scene under `tests/test_*.tscn` is a standalone headless suite: it prints
`PASS`/`FAIL` lines through `tests/test_support.gd`, ends with a
`--- <title>: N checks, M failures ---` summary and a `RESULT PASS`/`RESULT FAIL`
line, then quits with a matching exit code (spec 19.3).

Until now the only way to run all of them was a hand-written shell loop pasted
into a design document, with the test names spelled out one by one. That list
had gone stale - it named 20 suites while the folder holds 28, so eight were
never run by it. This script discovers the scenes instead, so a new
`tests/test_*.tscn` is picked up the moment it exists and cannot be forgotten.

    python tools/run_tests.py                 # every suite
    python tools/run_tests.py quest forge     # only suites matching these substrings
    python tools/run_tests.py --list          # show what would run, run nothing
    python tools/run_tests.py -v              # stream each suite's full output

Godot is found through the GODOT_PATH environment variable, then the known
install locations, then PATH - the same shape as `BLENDER_PATH` in
`tools/character_pipeline/pipeline.py`. On Windows the console build
(`Godot_console.exe`) is preferred and its absence is called out: plain
`Godot.exe` is a GUI-subsystem binary that does not write to a redirected
stdout, so a run through it produces no output to parse.

Four things are reported as failures beyond an honest `RESULT FAIL`:

* **TIMEOUT** - the suite never quit. This is a real failure mode here, not a
  hypothetical: a draft of `test_autoload_safety.gd` once omitted its
  `t.finish()` call and hung after printing all of its PASS lines. The shell
  loop had no timeout, so it hung with it.
* **ERROR** - the process ended without printing a RESULT line, which is what a
  parse error or a crash on load looks like. The shell loop's
  `grep RESULT | head -1` printed an empty cell for this and read as "fine".
* **a RESULT PASS that still exited non-zero**, which means the scene quit
  through some path other than `finish()`.
* **SCRIPT_ERROR** - a RESULT PASS with a `SCRIPT ERROR:` line anywhere in the
  output. A GDScript runtime error aborts only the function it fires in; the
  caller carries on, `finish()` still runs, and the suite passes with that
  function's checks silently missing from the count. `test_specials.gd` lost
  four assertions this way when `_resolve_board()` changed signature under
  it. Every such error is listed, with its `at:` location, under the table.
  WARNING lines are not failures.

Exits 0 only when every selected suite passed.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
TESTS_DIR = PROJECT / "tests"

# Godot's own quit code is the suite's failure count clamped to 1, so anything
# else came from the engine. Generous enough for test_economy's 1,000-run loops.
DEFAULT_TIMEOUT = 300

SUMMARY_RE = re.compile(r"^--- (?P<title>.+): (?P<checks>\d+) checks, (?P<failures>\d+) failures ---$")
ERROR_RE = re.compile(r"^\s*(?:USER )?(?:SCRIPT )?ERROR:", re.IGNORECASE)
# Only GDScript runtime errors: not push_error()'s "USER ERROR:", not engine
# "ERROR:" lines, and never "WARNING:".
SCRIPT_ERROR_RE = re.compile(r"^\s*SCRIPT ERROR:")


# --- locating Godot ---------------------------------------------------------------

def find_godot() -> Path:
    env = os.environ.get("GODOT_PATH", "")
    if env and Path(env).is_file():
        return Path(env)

    candidates: list[str] = []
    if os.name == "nt":
        # The console build first: see the module docstring on why the GUI one
        # is useless with a redirected stdout.
        candidates += sorted(glob.glob("C:/Projects/Godot/Godot/Godot_console.exe"))
        candidates += sorted(glob.glob("C:/Program Files/Godot/Godot_console.exe"))
        candidates += sorted(glob.glob("C:/Projects/Godot/Godot/Godot.exe"))
        candidates += sorted(glob.glob("C:/Program Files/Godot/Godot.exe"))
    for name in ("godot4", "godot", "Godot_console", "Godot"):
        found = shutil.which(name)
        if found:
            candidates.append(found)

    for candidate in candidates:
        if Path(candidate).is_file():
            return Path(candidate)
    sys.exit(
        "Godot not found. Set GODOT_PATH to the editor binary "
        "(on Windows use Godot_console.exe, not Godot.exe)."
    )


# --- discovering suites -----------------------------------------------------------

def discover(filters: list[str]) -> list[str]:
    """Every tests/test_*.tscn, narrowed to the ones matching any filter.

    The `test_` prefix is what keeps the two `_scratch_*` inspection scenes in
    the folder out of the suite; they are throwaway rigs, not tests.
    """
    names = sorted(p.stem for p in TESTS_DIR.glob("test_*.tscn"))
    if not filters:
        return names
    lowered = [f.lower() for f in filters]
    return [n for n in names if any(f in n.lower() for f in lowered)]


# --- running one suite ------------------------------------------------------------

class Result:
    def __init__(self, name: str, verdict: str, checks: int, failures: int,
                 seconds: float, note: str = "",
                 script_errors: list[str] | None = None) -> None:
        self.name = name
        self.verdict = verdict
        self.checks = checks
        self.failures = failures
        self.seconds = seconds
        self.note = note
        self.script_errors = script_errors or []

    @property
    def ok(self) -> bool:
        return self.verdict == "PASS"


def run_one(godot: Path, name: str, timeout: int, verbose: bool) -> Result:
    command = [
        str(godot), "--headless", "--path", str(PROJECT),
        f"res://tests/{name}.tscn",
    ]
    started = time.monotonic()
    try:
        proc = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout,
            encoding="utf-8", errors="replace",
        )
    except subprocess.TimeoutExpired:
        return Result(name, "TIMEOUT", 0, 0, time.monotonic() - started,
                      f"no RESULT line within {timeout}s - a missing finish() hangs like this")
    elapsed = time.monotonic() - started

    # Godot splits its output across both streams and, on Windows, terminates
    # lines with \r\n even when Python has already translated them.
    output = (proc.stdout or "") + (proc.stderr or "")
    lines = [line.rstrip("\r") for line in output.splitlines()]
    if verbose:
        print("\n".join(lines))

    checks = failures = 0
    for line in lines:
        match = SUMMARY_RE.match(line)
        if match:
            checks = int(match.group("checks"))
            failures = int(match.group("failures"))

    script_errors, script_error_total = _script_errors(lines)

    if "RESULT FAIL" in lines:
        return Result(name, "FAIL", checks, failures, elapsed,
                      script_errors=script_errors)
    if "RESULT PASS" in lines:
        if proc.returncode != 0:
            return Result(name, "ERROR", checks, failures, elapsed,
                          f"reported PASS but exited {proc.returncode}",
                          script_errors)
        if script_errors:
            plural = "" if script_error_total == 1 else "s"
            return Result(name, "SCRIPT_ERROR", checks, failures, elapsed,
                          f"{script_error_total} script error{plural}; checks may be missing",
                          script_errors)
        return Result(name, "PASS", checks, failures, elapsed)

    return Result(name, "ERROR", checks, failures, elapsed,
                  _error_note(lines, proc.returncode), script_errors)


def _with_location(lines: list[str], i: int) -> str:
    """Line i, joined with the "at: ..." line Godot puts the file:line on."""
    detail = lines[i].strip()
    if i + 1 < len(lines) and lines[i + 1].strip().startswith("at:"):
        detail = f"{detail} {lines[i + 1].strip()}"
    return detail


def _script_errors(lines: list[str]) -> tuple[list[str], int]:
    """Every distinct SCRIPT ERROR with its location, and the total fired.

    An error inside a loop fires once per iteration, so identical ones are
    folded into a single "(xN)" entry rather than flooding the summary.
    """
    counts: dict[str, int] = {}
    for i, line in enumerate(lines):
        if SCRIPT_ERROR_RE.match(line):
            detail = _with_location(lines, i)
            counts[detail] = counts.get(detail, 0) + 1
    entries = [d if n == 1 else f"{d} (x{n})" for d, n in counts.items()]
    return entries, sum(counts.values())


def _error_note(lines: list[str], returncode: int) -> str:
    """The first engine error in the output, or failing that the exit code.

    A suite that dies on load prints a parse error and nothing else; surfacing
    that first line is the difference between "something broke" and knowing
    which script broke.
    """
    for i, line in enumerate(lines):
        if ERROR_RE.match(line):
            return _with_location(lines, i)[:160]
    return f"no RESULT line; exited {returncode}"


# --- reporting --------------------------------------------------------------------

def report(results: list[Result]) -> int:
    width = max((len(r.name) for r in results), default=4)
    verdict_width = max((len(r.verdict) for r in results), default=7)
    print()
    for r in results:
        counts = f"{r.checks - r.failures}/{r.checks} checks" if r.checks else ""
        line = f"  {r.name:<{width}}  {r.verdict:<{verdict_width}} {counts:>16}  {r.seconds:6.1f}s"
        if r.note:
            line += f"  {r.note}"
        print(line)

    erroring = [r for r in results if r.script_errors]
    if erroring:
        print()
        print("  script errors:")
        for r in erroring:
            print(f"    {r.name}")
            for detail in r.script_errors:
                print(f"      {detail}")

    failed = [r for r in results if not r.ok]
    total_checks = sum(r.checks for r in results)
    plural = "suite" if len(failed) == 1 else "suites"
    print()
    print(f"  {len(results)} suites, {total_checks} checks, {len(failed)} {plural} failing")
    if failed:
        print("  failing: " + ", ".join(f"{r.name} ({r.verdict})" for r in failed))
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("filters", nargs="*",
                        help="substrings; a suite runs if its name contains any of them")
    parser.add_argument("--list", action="store_true",
                        help="print the suites that would run, then stop")
    parser.add_argument("--godot", help="path to the Godot binary (overrides GODOT_PATH)")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                        help=f"per-suite seconds before it counts as TIMEOUT (default {DEFAULT_TIMEOUT})")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="stream each suite's full output, not just its verdict")
    args = parser.parse_args()

    names = discover(args.filters)
    if not names:
        target = " matching " + ", ".join(args.filters) if args.filters else ""
        print(f"No test scenes found in tests/{target}.")
        return 1

    if args.list:
        for name in names:
            print(name)
        return 0

    godot = Path(args.godot) if args.godot else find_godot()
    if not godot.is_file():
        sys.exit(f"Godot binary not found at {godot}")
    print(f"Godot:  {godot}")
    print(f"Suites: {len(names)}")

    results: list[Result] = []
    for i, name in enumerate(names, 1):
        print(f"  [{i}/{len(names)}] {name} ... ", end="", flush=True)
        result = run_one(godot, name, args.timeout, args.verbose)
        print(result.verdict)
        results.append(result)

    return report(results)


if __name__ == "__main__":
    sys.exit(main())
