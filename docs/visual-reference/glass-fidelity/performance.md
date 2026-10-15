# Resource observations — 2026-10-15

Same Mac/display and user motion settings; two approximately five-minute live-agent observations,59 interval samples each. CPU is calculated from process cumulative CPU-time deltas divided by monotonic wall-time deltas, rather than ps lifetime-average %CPU.

| Metric | Before a2725dc | After83eb312 |
|---|---:|---:|
| App CPU mean (one core =100%) | 0.362 | 0.209 |
| App CPU P95 | 0.798 | 0.598 |
| RSS mean (MiB) | 152.819 | 112.236 |
| RSS P95 (MiB) | 152.859 | 112.359 |
| WindowServer CPU mean (system-wide) | 56.985 | 56.208 |

The after observation does not show an App CPU/RSS regression. It does not establish a causal performance improvement: the original process had run for about50minutes while the new process was fresh; session activity and other desktop/browser work were uncontrolled. WindowServer measurements include the entire desktop. GPU counters and a matched-fixture benchmark remain unmeasured.

After RSS first/last:112.094/112.375MiB; a single interval of this length cannot establish absence of a long-run leak.

Raw interval samples and summaries are stored alongside this report as before-resources.csv/after-resources.csv and matching JSON summaries.
