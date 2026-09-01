#!/usr/bin/env python3
"""Count WebGL shader program links in a Firefox performance profile.

Built for the town -> expedition transition investigation. The profile captured
on 2026-09-01 showed a 12.8 s freeze in exactly two requestAnimationFrame
callbacks, of which 12.4 s (97%) was WebGL shader compile + link:
61 program links totalling 11,715 ms, ten of which accounted for 83% of that.

The point of this script is to make each export variant a ten-second command
instead of an afternoon of ad-hoc JSON poking, so the variants in
`design documents/Sir Fish - Shader Link Counting Experiment.md` can be
compared like for like.

Usage:
    python tools/analyze_web_profile.py <profile.json.gz | profile.json> [--label NAME]

Capture a profile with the Firefox Profiler (https://profiler.firefox.com):
pick the "Graphics" preset, start recording, click a quest, wait for the
expedition to render, stop, then "Save as file" (that yields .json.gz).

The last line of output is a one-line SUMMARY suitable for pasting into the
results table in the experiment doc.
"""

from __future__ import annotations

import argparse
import gzip
import json
import statistics
import sys
from collections import Counter

# Markers Firefox emits for the two synchronous WebGL round-trips Godot's
# Compatibility backend forces. glLinkProgram is async in ANGLE until someone
# asks for the result -- Godot asks immediately, via
# glGetProgramiv(GL_LINK_STATUS), which is what turns each link into a blocking
# IPC wait on the GPU process.
LINK_MARKER = "PWebGL::Msg_GetLinkResult"
COMPILE_MARKER = "PWebGL::Msg_GetCompileResult"
RAF_MARKER = "requestAnimationFrame callbacks"

# A rAF callback longer than this is a stall, not a frame. Normal callbacks in
# this project run 1-9 ms; the stalls were 8361 ms and 4409 ms.
STALL_MS = 100.0

# Links slower than this are the ones worth eliminating. In the reference
# capture ten links cleared this bar and were 83% of all link time, while the
# other 51 together were 1,986 ms.
BIG_LINK_MS = 500.0


def load_profile(path: str) -> dict:
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as fh:
        return json.load(fh)


def pick_thread(profile: dict) -> tuple[int, dict, str]:
    """Return the thread that actually ran the game.

    Preference order: the thread carrying the most WebGL link/compile markers.
    That is more robust than matching the page URL, which changes between a
    GitHub Pages build and a local `python -m http.server` test.
    """
    strings = profile["shared"]["stringArray"]
    best = None
    for index, thread in enumerate(profile["threads"]):
        markers = thread["markers"]
        count = sum(
            1
            for j in range(markers["length"])
            if strings[markers["name"][j]] in (LINK_MARKER, COMPILE_MARKER)
        )
        if count and (best is None or count > best[0]):
            best = (count, index, thread)
    if best is None:
        sys.exit(
            "No WebGL shader markers found in any thread.\n"
            "Was the profile captured with the Graphics preset, and did the "
            "recording actually cover the transition?"
        )

    _, index, thread = best
    label = f"pid {thread.get('pid')} tid {thread.get('tid')} ({thread.get('name')})"
    return index, thread, label


def intervals(thread: dict, strings: list, name: str, t0: float) -> list[tuple[float, float]]:
    """Collect (start, duration) pairs for a marker, in milliseconds since t0.

    Firefox writes most of these as *paired* markers: phase 2 carries the real
    startTime and phase 3 the real endTime, with the opposite field holding a
    sentinel. Treating either as a self-contained interval yields nonsense
    timestamps, so the pairs are matched in emission order.
    """
    pending: float | None = None
    out: list[tuple[float, float]] = []
    markers = thread["markers"]
    for j in range(markers["length"]):
        if strings[markers["name"][j]] != name:
            continue
        phase = markers["phase"][j]
        if phase == 1:  # self-contained interval
            start, end = markers["startTime"][j], markers["endTime"][j]
            if start is not None and end is not None:
                out.append((start - t0, end - start))
        elif phase == 2:  # interval start
            pending = markers["startTime"][j]
        elif phase == 3 and pending is not None:  # interval end
            end = markers["endTime"][j]
            if end is not None:
                out.append((pending - t0, end - pending))
            pending = None
    out.sort()
    return out


def describe_frames(raf: list[tuple[float, float]], lo: float, hi: float, label: str) -> None:
    window = [f for f in raf if lo <= f[0] <= hi]
    if len(window) < 2:
        print(f"  {label}: too few frames to summarise")
        return
    gaps = [window[i][0] - window[i - 1][0] for i in range(1, len(window))]
    callbacks = [d for _, d in window]
    print(
        f"  {label}: {len(window):3d} frames  "
        f"median interval {statistics.median(gaps):5.1f} ms "
        f"(~{1000 / statistics.median(gaps):.0f} fps)  "
        f"median callback {statistics.median(callbacks):5.2f} ms  "
        f"max callback {max(callbacks):.1f} ms"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", help="Firefox profile (.json.gz or .json)")
    parser.add_argument("--label", default="", help="name for this variant in the SUMMARY line")
    parser.add_argument(
        "--list-links",
        action="store_true",
        help="print every program link, in order, with a duration bar",
    )
    args = parser.parse_args()

    profile = load_profile(args.profile)
    strings = profile["shared"]["stringArray"]
    t0 = profile["meta"]["profilingStartTime"]
    duration = profile["meta"]["profilingEndTime"] - t0

    index, thread, thread_label = pick_thread(profile)

    links = intervals(thread, strings, LINK_MARKER, t0)
    compiles = intervals(thread, strings, COMPILE_MARKER, t0)
    raf = intervals(thread, strings, RAF_MARKER, t0)

    link_ms = sum(d for _, d in links)
    compile_ms = sum(d for _, d in compiles)
    big = [x for x in links if x[1] > BIG_LINK_MS]
    big_ms = sum(d for _, d in big)

    stalls = [f for f in raf if f[1] > STALL_MS]
    stall_ms = sum(d for _, d in stalls)

    label = args.label or args.profile.rsplit("/", 1)[-1].rsplit("\\", 1)[-1]
    print(f"=== {label} ===")
    print(f"thread : {thread_label}  [index {index}]")
    print(f"capture: {duration:.0f} ms, {len(raf)} rAF frames")

    print(f"\n--- stalls (rAF callback > {STALL_MS:.0f} ms) ---")
    if stalls:
        for start, dur in stalls:
            print(f"  t={start:9.1f} ms   {dur:9.1f} ms")
        print(f"  total stalled: {stall_ms:.1f} ms")
    else:
        print("  none -- no callback exceeded the threshold")

    print("\n--- shader programs ---")
    print(f"  links          {len(links):4d} events  {link_ms:9.0f} ms")
    print(f"  compiles       {len(compiles):4d} events  {compile_ms:9.0f} ms")
    total = link_ms + compile_ms
    share = f"  ({100 * total / stall_ms:.1f}% of stall)" if stall_ms else ""
    print(f"  shader total                  {total:9.0f} ms{share}")
    if links:
        pct = 100 * big_ms / link_ms if link_ms else 0.0
        print(
            f"  links > {BIG_LINK_MS:.0f}ms  {len(big):4d} events  "
            f"{big_ms:9.0f} ms  ({pct:.1f}% of link time)"
        )

    # The reference capture's expensive links arrived in five near-identical
    # pairs, which is the main evidence that each spatial shader compiles two
    # variants. Bucketing by rounded duration makes a change in that structure
    # obvious at a glance.
    if big:
        print("\n--- expensive links, bucketed by duration (pairs are the signal) ---")
        buckets = Counter(round(d / 50) * 50 for _, d in big)
        for bucket in sorted(buckets, reverse=True):
            print(f"  ~{bucket:5d} ms  x{buckets[bucket]}")

    if args.list_links and links:
        print("\n--- every link, in order ---")
        running = 0.0
        for i, (start, dur) in enumerate(links, 1):
            running += dur
            print(
                f"  {i:3d}  t={start:9.1f}  {dur:8.1f} ms  "
                f"cum={running:8.0f}  {'#' * int(dur / 25)}"
            )

    if raf:
        print("\n--- frame health outside the stalls ---")
        first = stalls[0][0] if stalls else raf[-1][1]
        last = stalls[-1][0] + stalls[-1][1] if stalls else raf[0][0]
        describe_frames(raf, 0, first, "before")
        describe_frames(raf, last, float("inf"), "after ")

    print(
        f"\nSUMMARY  label={label}  links={len(links)}  link_ms={link_ms:.0f}  "
        f"big_links={len(big)}  big_ms={big_ms:.0f}  stall_ms={stall_ms:.0f}"
    )


if __name__ == "__main__":
    main()
