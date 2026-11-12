#!/usr/bin/env python3
"""The top functions of a Chrome .cpuprofile (tools/perf/web_run.mjs takes them): self time and total
(inclusive) time, in % of the samples. Usage: python3 tools/perf/cpu_top.py FILE.cpuprofile [N]"""
import collections
import json
import sys


def top(path, n=30):
    p = json.load(open(path))
    nodes = {x["id"]: x for x in p["nodes"]}
    parent = {}
    for x in p["nodes"]:
        for c in x.get("children", []):
            parent[c] = x["id"]
    counts = collections.Counter(p["samples"])
    total = sum(counts.values()) or 1
    name = lambda x: f'{x["callFrame"]["functionName"] or "(anonymous)"} {x["callFrame"]["url"].rsplit("/", 1)[-1]}'.strip()
    self_t, incl = collections.Counter(), collections.Counter()
    for nid, c in counts.items():
        self_t[name(nodes[nid])] += c
        seen, cur = set(), nid
        while cur is not None:
            k = name(nodes[cur])
            if k not in seen:
                incl[k] += c
                seen.add(k)
            cur = parent.get(cur)
    out = [f"{path}: {total} samples"]
    out.append("self %   total %   function")
    for k, c in self_t.most_common(n):
        out.append(f"{100 * c / total:6.1f}   {100 * incl[k] / total:6.1f}   {k}")
    out.append("--- by total (inclusive) ---")
    for k, c in incl.most_common(n):
        out.append(f"{100 * self_t[k] / total:6.1f}   {100 * c / total:6.1f}   {k}")
    return "\n".join(out)


if __name__ == "__main__":
    print(top(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 30))
