# Quickstart

This document shows the shortest path to loading and using `cl-py` from Common Lisp.

## Prerequisites

- SBCL installed
- Python 3 installed
- ASDF available
- Optional: Quicklisp for local interactive workflows

## 1. Bootstrap Python Dependencies

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/bootstrap-python.ps1
```

POSIX shell:

```sh
sh scripts/bootstrap-python.sh
```

After bootstrap, point `cl-py` at the managed interpreter:

Windows PowerShell:

```powershell
$env:CL_PY_PYTHON = ".venv/Scripts/python.exe"
```

POSIX shell:

```sh
export CL_PY_PYTHON=.venv/bin/python
```

## 2. Run the CLI Quickly

```sh
sbcl --script scripts/dev-cli.lisp help
sbcl --script scripts/dev-cli.lisp help http
sbcl --script scripts/dev-cli.lisp help registry
sbcl --script scripts/dev-cli.lisp help packaging
sbcl --script scripts/dev-cli.lisp help store
sbcl --script scripts/dev-cli.lisp help jobs
sbcl --script scripts/dev-cli.lisp registry
sbcl --script scripts/dev-cli.lisp json parse '{"name":"cl-py","active":true}'
sbcl --script scripts/dev-cli.lisp json emit '(("name" . "cl-py") ("active" . :true))'
sbcl --script scripts/dev-cli.lisp json normalize '{"b":2,"a":1}'
sbcl --script scripts/dev-cli.lisp time parse-iso 2026-03-29T10:20:30Z
sbcl --script scripts/dev-cli.lisp time format-iso '(:timestamp :year 2026 :month 3 :day 29 :hour 10 :minute 20 :second 30 :offset-minutes 0)'
sbcl --script scripts/dev-cli.lisp uri normalize HTTP://Example.COM:80/path?q=1
sbcl --script scripts/dev-cli.lisp http fetch-text http://127.0.0.1:8080/
sbcl --script scripts/dev-cli.lisp http fetch-json http://127.0.0.1:8080/data
sbcl --script scripts/dev-cli.lisp store snapshot-registry
sbcl --script scripts/dev-cli.lisp store list-registry
sbcl --script scripts/dev-cli.lisp store delete-registry nightly --force
sbcl --script scripts/dev-cli.lisp store delete-registry nightly snapshot-20260330 --dry-run
sbcl --script scripts/dev-cli.lisp store delete-registry --prefix nightly- --dry-run
sbcl --script scripts/dev-cli.lisp store delete-registry --created-before 2026-03-30T00:00:00Z --dry-run
sbcl --script scripts/dev-cli.lisp store delete-registry --created-after 2026-03-29T12:00:00Z --created-before 2026-03-31T00:00:00Z --dry-run
sbcl --script scripts/dev-cli.lisp store delete-registry nightly --dry-run
sbcl --script scripts/dev-cli.lisp store prune-registry 5 --force
sbcl --script scripts/dev-cli.lisp store prune-registry 5 --dry-run
sbcl --script scripts/dev-cli.lisp store latest-registry
sbcl --script scripts/dev-cli.lisp store summarize-registry nightly
sbcl --script scripts/dev-cli.lisp store diff-registry baseline nightly
sbcl --script scripts/dev-cli.lisp store adapter-history slugify
sbcl --script scripts/dev-cli.lisp store report-registry nightly
sbcl --script scripts/dev-cli.lisp store report-registry nightly --capability slugify-text
sbcl --script scripts/dev-cli.lisp store report-registry nightly --capability slugify-text --capability validate-instance
sbcl --script scripts/dev-cli.lisp store report-registry nightly --exclude-capability metadata
sbcl --script scripts/dev-cli.lisp store report-registry nightly --group capability
sbcl --script scripts/dev-cli.lisp store report-registry nightly --license-sort count-desc --capability-sort count-asc
sbcl --script scripts/dev-cli.lisp store report-registry nightly --license-limit 1 --capability-offset 1 --capability-limit 2
sbcl --script scripts/dev-cli.lisp store report-registry nightly --sort count-desc
sbcl --script scripts/dev-cli.lisp store report-registry nightly --sort count-desc --offset 1 --limit 2
sbcl --script scripts/dev-cli.lisp store report-registry nightly --sort count-desc --limit 2
sbcl --script scripts/dev-cli.lisp store report-registry nightly --output reports/nightly.json
sbcl --script scripts/dev-cli.lisp store report-registry nightly --license "MIT"
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --capability validate-instance
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --exclude-license "MIT"
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --group license
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --license-sort delta-desc --capability-sort name
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --license-limit 1 --capability-limit 2
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --sort delta-asc
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --sort abs-delta-desc
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --sort abs-delta-desc --offset 1 --limit 1
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --output reports/diff.json
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --sort delta-asc --limit 1
sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --license "MIT" --license "Apache-2.0"
sbcl --script scripts/dev-cli.lisp jobs demo-batch 2
sbcl --script scripts/dev-cli.lisp packaging metadata
sbcl --script scripts/dev-cli.lisp packaging normalize-version 1.0rc1
sbcl --script scripts/dev-cli.lisp dateutil metadata
sbcl --script scripts/dev-cli.lisp dateutil parse-isodatetime 2026-03-29T10:20:30+00:00
sbcl --script scripts/dev-cli.lisp slugify metadata
sbcl --script scripts/dev-cli.lisp slugify slugify-text "Hello Common Lisp"
sbcl --script scripts/dev-cli.lisp jsonschema metadata
```

On Windows PowerShell or other shells with difficult inline quoting, prefer file-backed input:

```powershell
Set-Content tmp.json '{"b":2,"a":1}'
sbcl --script scripts/dev-cli.lisp json normalize @tmp.json
```

The same pattern works for timestamps and timestamp forms:

```powershell
Set-Content tmp-time.txt '2026-03-29T10:20:30+05:30'
sbcl --script scripts/dev-cli.lisp time parse-iso @tmp-time.txt
```

The same `@file` and `-` input rules also apply to URI and HTTP commands.

If you give a malformed command, the CLI exits with code `2`. Runtime failures, such as a bad
HTTP response or missing Python adapter dependency, exit with code `1`.

Use `help <command>` to inspect either a native command group like `http` or an adapter group like
`packaging` without running the command itself.

For native command groups, help output also includes accepted input forms and ready-to-run
examples, which is useful on shells where quoting rules vary.

Registry snapshots are stored under `.cl-py-store/registry/` by default. Set `CL_PY_STORE_DIR`
before running the CLI if you want to keep snapshots in another directory.

The store layer can also answer simple snapshot queries such as latest snapshot id, per-snapshot
summary, snapshot-to-snapshot diffs, adapter history across snapshots, and aggregate reports,
including reports filtered by one or more licenses or capabilities, sorted aggregate rows,
aggregate report diffs, exclusion filters, group-selected output, row limits, offsets,
absolute-delta sorting, per-group sort overrides, per-group paging overrides, file export,
per-result pagination metadata such as total, returned, and remaining row counts, plus lifecycle
operations for deleting snapshots and pruning older snapshots while keeping the newest N entries.
Use `--dry-run` on delete/prune commands to preview changes without modifying the store, and
use `--force` to execute the actual destructive operation.
Lifecycle delete/prune JSON responses also include an `audit` object with the operation name,
execution mode, timestamp, and store root for downstream logging.
`store delete-registry` accepts one or more snapshot ids so cleanup batches can be previewed or
executed in a single command.
It also accepts repeated `--prefix <text>` selectors to target matching snapshot ids without
spelling out each id explicitly.
Use `--created-before <ISO-8601>` to target snapshots older than a specific creation timestamp.
Combine `--created-after` with `--created-before` to target snapshots within a bounded time window.
Lifecycle cleanup responses now also expose `before-count`, `after-count`, and `would-after-count`
so scripts can compare actual and projected snapshot totals directly.
Delete responses also expose a `matched` object so scripts can distinguish explicit id matches,
prefix matches, and time-window matches.
They also expose a `summary` object that groups `deleted-count`, `before-count`,
`after-count`, `would-after-count`, and a shared `affected-count` into one stable sub-object.
That object now also includes `explicit-count`, `prefix-count`, and `created-window-count`
for callers that only need per-source totals.
It also includes `total-matched-count`, which is deduplicated across all selector sources.

Example dry-run response for a mixed selector request such as:

```sh
sbcl --script scripts/dev-cli.lisp store delete-registry nightly-20260329 --prefix nightly- --created-after 2026-03-29T12:00:00Z --created-before 2026-03-31T00:00:00Z --dry-run
```

```json
{
	"deleted": false,
	"dry-run": true,
	"forced": false,
	"would-delete": true,
	"before-count": 7,
	"after-count": 7,
	"would-after-count": 4,
	"deleted-count": 3,
	"summary": {
		"affected-count": 3,
		"before-count": 7,
		"after-count": 7,
		"would-after-count": 4,
		"deleted-count": 3
	},
	"snapshot-ids": [
		"nightly-20260329",
		"nightly-20260330",
		"nightly-20260330-hotfix"
	],
	"prefixes": [
		"nightly-"
	],
	"created-before": "2026-03-31T00:00:00Z",
	"created-after": "2026-03-29T12:00:00Z",
	"matched": {
		"explicit-snapshot-ids": [
			"nightly-20260329"
		],
		"explicit-count": 1,
		"prefix-snapshot-ids": [
			"nightly-20260329",
			"nightly-20260330",
			"nightly-20260330-hotfix"
		],
		"prefix-count": 3,
		"created-window-snapshot-ids": [
			"nightly-20260330"
		],
		"created-window-count": 1,
		"total-matched-count": 3
	},
	"audit": {
		"operation": "delete-registry",
		"mode": "dry-run",
		"executed-at": "2026-03-30T11:42:15Z",
		"store-root": ".cl-py-store"
	}
}
```

In that example, `1 + 3 + 1 != total-matched-count` because the same snapshot can be matched by
more than one selector source. `total-matched-count` reflects the deduplicated set that would
actually be affected by the delete request.

Example dry-run response for a prune request such as:

```sh
sbcl --script scripts/dev-cli.lisp store prune-registry 2 --dry-run
```

```json
{
	"dry-run": true,
	"forced": false,
	"before-count": 7,
	"after-count": 7,
	"would-after-count": 2,
	"summary": {
		"affected-count": 5,
		"before-count": 7,
		"after-count": 7,
		"would-after-count": 2,
		"keep-count": 2,
		"kept-count": 2,
		"deleted-count": 5
	},
	"audit": {
		"operation": "prune-registry",
		"mode": "dry-run",
		"executed-at": "2026-03-30T11:47:02Z",
		"store-root": ".cl-py-store",
		"keep-count": 2,
		"kept-count": 2,
		"deleted-count": 5
	},
	"keep-count": 2,
	"kept-count": 2,
	"deleted-count": 5,
	"kept-snapshot-ids": [
		"nightly-20260331",
		"nightly-20260330"
	],
	"deleted-snapshot-ids": [
		"nightly-20260329",
		"nightly-20260328",
		"nightly-20260327",
		"nightly-20260326",
		"nightly-20260325"
	]
}
```

This response shape is useful when automation needs both the projected post-prune size
(`would-after-count`) and the exact snapshot ids that would be kept or removed.
Prune responses also expose a `summary` object that groups `keep-count`, `kept-count`,
`deleted-count`, `before-count`, `after-count`, `would-after-count`, and a shared
`affected-count` into one stable
sub-object for script consumers.

## Lifecycle Response Fields

Shared lifecycle fields returned by both `store delete-registry` and `store prune-registry`:

- `dry-run`: `true` when the command is a preview and does not remove files
- `forced`: `true` when the destructive operation was explicitly executed with `--force`
- `before-count`: current number of snapshots before the lifecycle operation is applied
- `after-count`: actual number of snapshots after the call returns; in preview mode this stays equal to `before-count`
- `would-after-count`: projected number of snapshots after the destructive operation would complete
- `audit.operation`: lifecycle operation name such as `delete-registry` or `prune-registry`
- `audit.mode`: `dry-run` or `force`
- `audit.executed-at`: ISO-8601 timestamp for when the lifecycle response was produced
- `audit.store-root`: resolved store root used by the command
- `summary.affected-count`: number of snapshots materially affected by the lifecycle plan; for delete and prune this is the number of snapshots selected for removal

Delete-specific fields returned by `store delete-registry`:

- `deleted`: `true` only when snapshot files were actually removed
- `would-delete`: `true` during preview mode to indicate the request resolved at least one deletion target
- `summary.deleted-count`: number of unique snapshots selected for deletion
- `summary.before-count`: current snapshot total before deletion
- `summary.after-count`: actual snapshot total after the call returns
- `summary.would-after-count`: projected snapshot total after the delete plan completes
- `deleted-count`: number of unique snapshots selected for deletion
- `snapshot-ids`: deduplicated snapshot ids that would be removed or were removed
- `prefixes`: repeated `--prefix` selectors echoed back in normalized order
- `created-before`: echoed upper timestamp bound or `null`
- `created-after`: echoed lower timestamp bound or `null`
- `matched.explicit-snapshot-ids`: snapshot ids matched directly from positional arguments
- `matched.explicit-count`: count of explicit id matches
- `matched.prefix-snapshot-ids`: snapshot ids matched through `--prefix`
- `matched.prefix-count`: count of prefix-based matches
- `matched.created-window-snapshot-ids`: snapshot ids matched through `--created-after` and/or `--created-before`
- `matched.created-window-count`: count of time-window matches
- `matched.total-matched-count`: deduplicated total across all selector sources

Prune-specific fields returned by `store prune-registry`:

- `summary.keep-count`: requested number of newest snapshots to retain
- `summary.kept-count`: number of snapshots retained by the prune plan
- `summary.deleted-count`: number of snapshots removed or scheduled for removal
- `summary.before-count`: current snapshot total before pruning
- `summary.after-count`: actual snapshot total after the call returns
- `summary.would-after-count`: projected snapshot total after the prune plan completes
- `keep-count`: requested number of newest snapshots to retain
- `kept-count`: number of snapshots that remain after pruning or would remain after execution
- `deleted-count`: number of snapshots removed or scheduled for removal by the prune plan
- `kept-snapshot-ids`: newest snapshot ids retained by the prune plan
- `deleted-snapshot-ids`: older snapshot ids removed or scheduled for removal by the prune plan

The `jobs demo-batch` command emits structured JSON results and is the current CLI entry for the
native bounded task runner.

## 3. Load with ASDF from the Repository Root

Start SBCL in the repository root and load the system:

```lisp
(require "asdf")
(asdf:load-system #:cl-py)
```

Then call exported functions directly:

```lisp
(cl-py:parse-json "{\"name\":\"cl-py\",\"active\":true}")
(cl-py:emit-json '(("name" . "cl-py") ("active" . :true)))
(cl-py:normalize-json "{\"b\":2,\"a\":1}")
(cl-py:parse-iso-timestamp "2026-03-29T10:20:30Z")
(cl-py:format-iso-timestamp '(:timestamp :year 2026 :month 3 :day 29 :hour 10 :minute 20 :second 30 :offset-minutes 0))
(cl-py:normalize-uri "HTTP://Example.COM:80/path?q=1")
(cl-py:fetch-text "http://127.0.0.1:8080/")
(cl-py:fetch-json "http://127.0.0.1:8080/data")
(cl-py:list-adapters)
(cl-py:adapter-metadata "packaging")
(cl-py:normalize-packaging-version "1.0rc1")
(cl-py:adapter-metadata "dateutil")
(cl-py:parse-dateutil-isodatetime "2026-03-29T10:20:30+00:00")
(cl-py:adapter-metadata "slugify")
(cl-py:slugify-text "Hello Common Lisp")
(cl-py:adapter-metadata "jsonschema")
(cl-py:validate-jsonschema-instance
 "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}"
 "{\"name\":\"cl-py\"}")
```

## 4. Load with Quicklisp for Local Development

If you use Quicklisp, the cleanest workflow is to add the repository to Quicklisp's local projects.

Typical path:

```text
~/quicklisp/local-projects/
```

Create a symlink or clone the repository there, then in SBCL:

```lisp
(ql:quickload :cl-py)
```

If you cloned the repository elsewhere, you can still register it manually through ASDF by pushing
the repository root onto `asdf:*central-registry*`, but using Quicklisp local-projects is simpler
and less error-prone.

## 5. Run the Smoke Tests

```sh
sbcl --script scripts/run-tests.lisp
```

The smoke suite always checks the registry and metadata surface. The Python-backed packaging test is
best-effort and will be skipped if Python or the required module is unavailable.

## 6. What Gets Loaded

At load time, `cl-py`:

- Loads the core Common Lisp system
- Loads native JSON helpers for stable internal data handling
- Loads native time normalization helpers for timestamp parsing and formatting
- Loads native URI/HTTP helpers for normalization and loopback-safe fetch workflows
- Reads adapter manifests from `adapters/manifests/`
- Registers adapters in memory
- Exposes adapter metadata and user-facing functions through the `cl-py` package

That means adding a new adapter usually involves three distinct artifacts:

- A manifest file
- A Python dependency declaration in `requirements/adapters/`
- A Common Lisp implementation file under `src/adapters/`
