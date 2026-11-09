# File Provider change delivery latency

The November 4, 2026 trace of build 35.0.0.18 showed 47.085 seconds from
server creation to a dataless placeholder, 53.594 seconds for a returning server
edit, and 44.592 seconds for an edit following a client restart. Initial hydration
itself took 0.854 seconds. A second trace with Finder open measured 50.521 seconds
for the returning edit; its directory request took 0.23 seconds. The delay was the
30-second application poll followed by a completed working-set scan barrier.

The File Provider extension adds a refresh timer to inspect the
account root every five seconds, with one request in flight and a ten-second
request timeout. It does not depend on regular directory enumerator lifetimes.
The application's existing poll and push signals remain compatible.

A domain-owned scan publishes completed reads to short change enumerations while
unrelated reads continue. Intermediate responses retain the incoming sync anchor;
deletions and same-path identity replacements wait for reconciliation. The final
response advances only to the scan's starting time. Realm rows replay discoveries
across enumerator/extension replacement, including unmaterialized children whose
parent etag did not change. Snapshots resolve identifiers against current rows so
newer local versions are not overwritten by an older scan result. New notifications
cancel obsolete scans; replacements wait for cancelled reads to finish persisting.
Failed scans retry once after five seconds and retain their incoming anchor.
After a second failure, the next change notification is required to start another scan.
The root poll shares NextcloudKit's data session and its per-host connection limit;
it does not reserve a connection ahead of scans or file transfers.

## Mock benchmark

`RemoteChangePropagationTests.testWorkingSetDeliveryLatencyBenchmark` compares the
blocking path and incremental path using 716 visited folders and six concurrent
reads, with mocked network delay scaled to 20 milliseconds per request. It measures
completion of a response containing the changed file, not just `didUpdate`.
No live API is called. November 4 release-candidate source, debug test build:

| Run | Blocking response | Incremental response |
| --- | --- | --- |
| 1 | 3.225 seconds | 0.202 seconds |
| 2 | 3.417 seconds | 0.208 seconds |

These are scaled mock timings, not a live latency guarantee. Deterministic regression
coverage also suspends unrelated reads, checks an unchanged intermediate anchor,
defers deletions, replays cached children, rejects partial case-insensitive path
replacements, resolves newer metadata, and serializes cancelled scans.

## Qualification

After John's explicit Apple-submission approval, build 35.0.0.19 was accepted,
stapled and installed. Deep signature verification and Gatekeeper passed. The
existing account, domain, entitlement groups, dependencies and artwork were preserved.

The live test used N5's existing WARP Mesh route with strict SSH host-key checking
while this Mac was away from the LAN. Server creation reached a dataless,
zero-allocation placeholder in 5.753 seconds, followed by 0.907 seconds of hydration.
The Mac edit was observed on the server after 0.973 seconds; the returning web edit
arrived within 9.084 seconds and the edit after a supported app restart within
6.538 seconds. These server-origin values are conservative upper bounds. The
one-off ten-second timing gate passed. John confirmed the file is visible in Finder without a Sign In banner on November 5,
completing the visual acceptance check.

Full deletion/move reconciliation still waits for the bounded scan. The passing
live gate covers creation, content edits, on-demand hydration, upload and restart.
The website's published download remains build 18; no download replacement,
commit, merge, push or website deployment occurred in this task.

The final fixture was moved to verified recoverable Trash on November 5 and
removed from the local domain after the helper completed the normal deletion
cache notification. No additional desktop-client code change was needed for cleanup.
Acceptance and temporary-file cleanup are complete.
