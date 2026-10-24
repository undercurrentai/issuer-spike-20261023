# Normalized-output definition (pre-registered before any stage run)

Spike: AR-B section 7 item 1 (issuer spike, 2026-10-23). This file is written and digested
BEFORE the first stage run (council #18, Sol seat). `normalize.py` implements exactly these
rules and nothing else. If a run shows a difference that these rules do not remove, the
difference is reported; the rules are not widened after the fact.

## Inputs to normalization

Each run passes three absolute roots: `SRC` (fixture checkout), `DEPS` (locked dependency
target dir), `OUT` (stage output dir). They differ by runner and are not part of the output.

## N1. JUnit XML (`raw/junit.xml` -> `norm/junit.xml`)

1. Parse the XML (stdlib `xml.etree.ElementTree`).
2. On every element, delete these attributes if present: `timestamp`, `time`, `hostname`.
3. In every remaining attribute value and every text/tail node, replace:
   - each occurrence of the literal `SRC`, `DEPS`, `OUT` root strings with `<SRC>`, `<DEPS>`, `<OUT>`
     (longest root first);
   - memory addresses matching `0x[0-9a-fA-F]{6,}` with `0x<ADDR>`.
4. Do NOT reorder test cases or suites. Order is part of the measured output.
5. Serialize with W3C Canonical XML 2.0 (`xml.etree.ElementTree.canonicalize`, `strip_text=True`),
   UTF-8, plus one trailing newline.

Kept (must match): suite name, `tests`, `failures`, `errors`, `skipped` counts, every
`testcase` `classname` and `name` in order, every failure/error/skip element, its `type`,
`message`, and text after rule 3.

## N2. Coverage JSON (`raw/coverage.json` -> `norm/coverage.json`)

1. Parse JSON.
2. Delete `meta.timestamp`. Keep every other `meta` field (including `version`, `format`,
   `branch_coverage`, `show_contexts`): the tool version is pinned, so it must match.
3. Rewrite each key of `files`: if it starts with `SRC` + `/`, strip that prefix. (The spec's
   coveragerc sets `relative_files = True`, so this is expected to be a no-op.)
4. Serialize with `sort_keys=True`, `separators=(",", ":")`, `ensure_ascii=False`, UTF-8,
   plus one trailing newline.

Kept (must match): per-file executed/missing/excluded lines, branches, summaries, totals.

## N3. Summary (`norm/summary.json`, derived; the facts an envelope would carry)

Integers and strings only (KTD3 rejects floats): JUnit `tests`, `failures`, `errors`,
`skipped`; coverage `covered_lines`, `num_statements`, `num_branches`, `covered_branches`,
`missing_lines`, and `percent_covered_display` (string). Serialized as in N2.4.

## Digests

`sha256` over the exact bytes of each `norm/*` file. Raw files (`raw/junit.xml`,
`raw/coverage.json`) are digested too and kept; raw differences alone do not establish
irreproducibility (AR-B section 7 item 1). The match verdict uses `norm/junit.xml` and
`norm/coverage.json` (N1, N2). `norm/summary.json` is reported for information.

## Match verdict

- MATCH: N1 and N2 digests are identical between the CI job and the local container run of the
  same stage spec on the same subject digest and the same image platform digest.
- MISMATCH: any N1 or N2 digest differs -> stop and report under the kill criterion
  "issuer cannot be made reproducible" (plan line 112), with the diff.
