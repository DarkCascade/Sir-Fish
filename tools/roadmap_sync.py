"""Snapshot the Sir Fish GitHub board for the roadmap artifact.

The roadmap (https://claude.ai/artifact/SZAy7uB2eMLr1TRVbfzKbX) plans the work; the GitHub
project is where status lives. The page cannot reach GitHub itself, so this writes one JSON
document that Claude stores as `meta/github` in the artifact's database:

    python tools/roadmap_sync.py <out.json>

then ArtifactData `set` on collection `meta`, doc `github`, with `file_path` = <out.json>.
Each task row's `issues` list is matched against this snapshot; a task with issues reads as
done once all of them are closed.
"""
import json, subprocess, sys
from datetime import datetime, timezone

REPO = "DarkCascade/Sir-Fish"


def gh(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        sys.exit(r.stderr)
    return json.loads(r.stdout)


def main(out_path):
    columns = {}
    for item in gh("project", "item-list", "3", "--owner", "DarkCascade", "--limit", "500", "--format", "json")["items"]:
        content = item.get("content") or {}
        if content.get("type") == "Issue":
            columns[content["number"]] = item.get("status") or ""
    issues = {}
    for issue in gh("issue", "list", "--repo", REPO, "--state", "all", "--limit", "1000",
                    "--json", "number,title,state,milestone"):
        n = issue["number"]
        issues[str(n)] = {
            "t": issue["title"],
            "st": issue["state"].lower(),
            "col": columns.get(n, ""),
            "ms": (issue.get("milestone") or {}).get("title", ""),
        }
    doc = {"repo": REPO, "syncedAt": datetime.now(timezone.utc).isoformat(timespec="minutes"), "issues": issues}
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(issues)} issues, {sum(1 for i in issues.values() if i['st'] == 'open')} open -> {out_path}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "roadmap_github.json")
