# Development Guide

This guide describes the intended local workflow for working on `cl-py`.

## Development Model

`cl-py` is intentionally split into three layers:

1. Common Lisp core
2. Adapter metadata and compatibility declarations
3. Python dependency boundary

Keep product-facing logic in Common Lisp. Python should remain a declared dependency boundary, not
the place where repository behavior silently moves.

## Recommended Local Setup

1. Install SBCL.
2. Install Python 3.
3. Bootstrap the managed Python environment.
4. Set `CL_PY_PYTHON` to the interpreter in `.venv`.
5. Load the system through ASDF or Quicklisp.

Minimal setup flow:

```sh
sh scripts/bootstrap-python.sh
export CL_PY_PYTHON=.venv/bin/python
sbcl --script scripts/run-tests.lisp
```

Windows PowerShell equivalent:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/bootstrap-python.ps1
$env:CL_PY_PYTHON = ".venv/Scripts/python.exe"
sbcl --script scripts/run-tests.lisp
```

## Working with ASDF

Primary systems:

- `cl-py`
- `cl-py-tests`

Common actions from a REPL:

```lisp
(require "asdf")
(asdf:load-system #:cl-py)
(asdf:test-system #:cl-py-tests)
```

When source files change during a REPL session, reload the system instead of trying to patch state
by hand:

```lisp
(asdf:load-system #:cl-py :force t)
```

## Working with Quicklisp

Quicklisp is not required for CI, but it is useful for iterative local work. Recommended practice:

- Put the repository in Quicklisp `local-projects`
- Load with `ql:quickload`
- Keep ASDF system names aligned with repository purpose

This avoids custom `asdf:*central-registry*` state on every machine.

## Adding a New Adapter

For each adapter, add all of the following:

1. Manifest in `adapters/manifests/`
2. Python requirement file in `requirements/adapters/`
3. Common Lisp implementation in `src/adapters/`
4. CLI command registration if the capability should be user-accessible from the dev CLI
5. Smoke coverage or richer contract tests

Suggested checklist:

- Pick a high-quality upstream library
- Confirm license compatibility
- Define a narrow capability slice
- Declare Python version and dependency range
- Add meaningful failure behavior
- Exercise the feature from Common Lisp, not only from Python

## Repository Conventions

- `src/` holds Common Lisp implementation code
- `src/adapters/` holds adapter-specific Common Lisp behavior
- `adapters/manifests/` holds adapter metadata
- `requirements/adapters/` holds Python requirement declarations by adapter
- `scripts/` holds bootstrap and entrypoint scripts
- `tests/` holds smoke or broader automated checks

## Debugging Tips

If the registry loads but an adapter call fails, check these in order:

1. Is `CL_PY_PYTHON` pointing at the intended interpreter?
2. Does the target interpreter have the required Python package installed?
3. Does the adapter manifest match the upstream module name?
4. Is the capability implemented in the Common Lisp adapter file?

Useful commands:

```sh
sbcl --script scripts/dev-cli.lisp registry
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
sbcl --script scripts/dev-cli.lisp dateutil metadata
sbcl --script scripts/dev-cli.lisp slugify metadata
sbcl --script scripts/dev-cli.lisp jsonschema metadata
sbcl --script scripts/run-tests.lisp
```

## Local Snapshot Store

The native store layer writes registry snapshots under `.cl-py-store/registry/` by default.

- Use `CL_PY_STORE_DIR` to redirect the store root to another directory
- Snapshots are written as canonical JSON for easy inspection and reuse
- The current first slice is intentionally small and focused on registry persistence
- Query helpers now cover latest snapshot lookup, summary output, snapshot diffs, adapter history, aggregate reports, repeated filter flags, exclusion filters, group-selected output, row sorting, row offsets, row limits, per-group sort overrides, per-group paging overrides, absolute-delta sorting, file export, aggregate report diffs, snapshot deletion, and snapshot pruning
- Delete/prune lifecycle commands require `--force` for destructive execution and support `--dry-run` so cleanup plans can be inspected before any files are removed
- Lifecycle delete/prune responses now include structured `audit` metadata with operation, mode, execution time, and store root information
- `store delete-registry` can remove multiple snapshot ids in one call, with the same `--force` and `--dry-run` safety model
- `store delete-registry` also accepts repeated `--prefix` selectors so snapshot cleanup batches can be addressed by naming convention
- `store delete-registry` also accepts `--created-before` so cleanup batches can be selected by snapshot creation time using native ISO timestamp parsing
- `store delete-registry` also accepts `--created-after` so time-window cleanup can be expressed as native lower/upper ISO timestamp bounds
- Lifecycle delete/prune responses now also include before/after snapshot totals so callers can measure current and projected cleanup impact without recomputing store state
- Delete responses now also include selector match breakdowns so callers can distinguish explicit, prefix, and time-window matches in preview and execution flows
- Those selector breakdowns also include per-source count fields so callers can consume match totals without re-counting JSON arrays
- Report and diff-report payloads now include per-row-set pagination objects so callers can track total, returned, and remaining rows after offset/limit are applied

## Native Concurrency Runner

The current concurrency slice is intentionally narrow.

- Use `run-bounded-task-batch` for reusable bounded parallel work in Common Lisp
- Use `jobs demo-batch` to exercise the runner from the CLI
- Task failures are returned as structured results so the whole batch remains inspectable

## CI Expectations

The current CI workflow performs:

- checkout
- Python setup
- SBCL installation
- Python bootstrap
- CLI registry run
- smoke tests

New changes should preserve that path. If a feature requires more setup, update both the local
bootstrap flow and CI so they stay aligned.
