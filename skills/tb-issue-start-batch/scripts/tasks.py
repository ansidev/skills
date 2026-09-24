#!/usr/bin/env python3
"""Queue manager for the tb-issue-start-batch skill.

State lives in a single JSON file (default `.agents/tb-batch/tasks.json`,
relative to the repository root) that can hold several batches keyed by a
batch id derived from the batch's ticket ids, so re-running the same prompt
finds and resumes the same batch. All writes are atomic (temp file + rename);
only the parent agent runs this script — child agents never touch the file.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import tempfile

DEFAULT_FILE = ".agents/tb-batch/tasks.json"
STATUSES = ("pending", "in_progress", "done", "failed")


def utcnow():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load(path):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    return {"version": 1, "batches": {}}


def save(path, data):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tasks-", suffix=".json", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def make_batch_id(ticket_ids):
    return hashlib.sha1(",".join(sorted(ticket_ids)).encode()).hexdigest()[:8]


def find_ticket(batch, ticket_id):
    for ticket in batch["tickets"]:
        if ticket["id"] == ticket_id:
            return ticket
    return None


def detect_cycle(tickets):
    """Return a list of ticket ids forming a dependency cycle, or None."""
    ids = {t["id"] for t in tickets}
    graph = {
        t["id"]: [d for d in t.get("depends_on", []) if d in ids]
        for t in tickets
    }
    state = {}  # 0 = unvisited, 1 = in progress, 2 = done

    def visit(node, path):
        state[node] = 1
        for dep in graph.get(node, []):
            if state.get(dep, 0) == 1:
                return path + [node, dep]
            if state.get(dep, 0) == 0:
                cycle = visit(dep, path + [node])
                if cycle:
                    return cycle
        state[node] = 2
        return None

    for ticket in tickets:
        if state.get(ticket["id"], 0) == 0:
            cycle = visit(ticket["id"], [])
            if cycle:
                return cycle
    return None


def deps_satisfied(ticket, batch):
    """Deps not tracked in the batch count as satisfied (verified upstream)."""
    statuses = {t["id"]: t["status"] for t in batch["tickets"]}
    return all(statuses.get(d, "done") == "done" for d in ticket.get("depends_on", []))


def cmd_init(args):
    deps = {}
    for pair in args.dep or []:
        if "=" not in pair:
            sys.exit(f"error: --dep expects <ticket-id>=<depends-on-id>, got: {pair}")
        child, parent = pair.split("=", 1)
        deps.setdefault(child, []).append(parent)

    data = load(args.file)
    batch_id = args.batch_id or make_batch_id(args.ticket)
    batch = data["batches"].get(batch_id)
    created = batch is None
    if created:
        batch = {"batch_id": batch_id, "created_at": utcnow(), "tickets": []}
        data["batches"][batch_id] = batch

    requested = list(dict.fromkeys(args.ticket))
    for dep_child, dep_parents in deps.items():
        if dep_child not in requested:
            sys.exit(f"error: --dep references ticket {dep_child} which is not part of the batch")

    for ticket_id in requested:
        ticket = find_ticket(batch, ticket_id)
        if ticket is None:
            batch["tickets"].append({
                "id": ticket_id,
                "depends_on": sorted(deps.get(ticket_id, [])),
                "status": "pending",
                "base_branch": None,
                "branch": ticket_id,
                "worktree": None,
                "agent": None,
                "commit": None,
                "note": None,
                "updated_at": utcnow(),
            })
        else:
            # Resume: keep status and progress; refresh the dependency graph.
            ticket["depends_on"] = sorted(deps.get(ticket_id, []))
            ticket.setdefault("status", "pending")
            for key in ("base_branch", "branch", "worktree", "agent", "commit", "note"):
                ticket.setdefault(key, None)
            ticket["updated_at"] = utcnow()

    cycle = detect_cycle(batch["tickets"])
    if cycle:
        if created:
            # A brand-new batch with a cycle must not pollute the queue file.
            data["batches"].pop(batch_id, None)
        save(args.file, data)
        sys.exit("error: dependency cycle detected: " + " -> ".join(cycle))

    save(args.file, data)
    print(json.dumps(batch, indent=2))


def cmd_show(args):
    data = load(args.file)
    batch = data["batches"].get(args.batch_id)
    if batch is None:
        sys.exit(f"error: batch {args.batch_id} not found in {args.file}")
    tickets = batch["tickets"]
    if args.status:
        tickets = [t for t in tickets if t["status"] == args.status]
    print(json.dumps({"batch_id": batch["batch_id"], "tickets": tickets}, indent=2))


def cmd_ready(args):
    data = load(args.file)
    batch = data["batches"].get(args.batch_id)
    if batch is None:
        sys.exit(f"error: batch {args.batch_id} not found in {args.file}")
    ready = [
        t for t in batch["tickets"]
        if t["status"] == "pending" and deps_satisfied(t, batch)
    ]
    print(json.dumps(ready, indent=2))


def cmd_set(args):
    if args.status and args.status not in STATUSES:
        sys.exit(f"error: status must be one of {', '.join(STATUSES)}")
    data = load(args.file)
    batch = data["batches"].get(args.batch_id)
    if batch is None:
        sys.exit(f"error: batch {args.batch_id} not found in {args.file}")
    ticket = find_ticket(batch, args.ticket)
    if ticket is None:
        sys.exit(f"error: ticket {args.ticket} not found in batch {args.batch_id}")

    for key in ("status", "base_branch", "branch", "worktree", "agent", "commit", "note"):
        value = getattr(args, key)
        if value is not None:
            ticket[key] = value
    for pair in args.field or []:
        if "=" not in pair:
            sys.exit(f"error: --field expects <key>=<value>, got: {pair}")
        key, value = pair.split("=", 1)
        ticket[key] = value
    ticket["updated_at"] = utcnow()

    save(args.file, data)
    print(json.dumps(ticket, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", default=DEFAULT_FILE, help=f"queue file path (default: {DEFAULT_FILE})")
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init", help="create or resume a batch")
    p_init.add_argument("--batch-id", help="batch id (default: derived from ticket ids)")
    p_init.add_argument("--ticket", action="append", required=True, help="ticket id, repeatable")
    p_init.add_argument("--dep", action="append", metavar="CHILD=PARENT",
                        help="dependency edge, repeatable")
    p_init.set_defaults(func=cmd_init)

    p_show = sub.add_parser("show", help="print batch tickets as JSON")
    p_show.add_argument("--batch-id", required=True)
    p_show.add_argument("--status", choices=STATUSES, help="filter by status")
    p_show.set_defaults(func=cmd_show)

    p_ready = sub.add_parser("ready", help="print startable (pending, unblocked) tickets as JSON")
    p_ready.add_argument("--batch-id", required=True)
    p_ready.set_defaults(func=cmd_ready)

    p_set = sub.add_parser("set", help="update one ticket's fields")
    p_set.add_argument("--batch-id", required=True)
    p_set.add_argument("--ticket", required=True)
    p_set.add_argument("--status", choices=STATUSES)
    for key in ("base_branch", "branch", "worktree", "agent", "commit", "note"):
        p_set.add_argument(f"--{key.replace('_', '-')}")
    p_set.add_argument("--field", action="append", metavar="KEY=VALUE",
                       help="set any extra field, repeatable")
    p_set.set_defaults(func=cmd_set)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
