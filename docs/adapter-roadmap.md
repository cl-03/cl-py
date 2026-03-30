# Native Capability Roadmap

This document turns the current Common Lisp ecosystem catalog into a practical build order for the
next `cl-py` capabilities.

Under the current constitution, the default path is native Common Lisp implementation. Existing
Python-backed adapters remain valid as narrow compatibility seams, but they are no longer the
repository's primary growth strategy.

## Selection Method

The current shortlist uses five filters:

1. The capability is already visible in the curated Common Lisp ecosystem catalog.
2. A native Common Lisp library can satisfy the first user-facing slice with reasonable quality.
3. The first delivery can be small, testable, and useful from the CLI and Lisp API.
4. The work strengthens reusable project infrastructure rather than adding one-off glue.
5. Any future interop need would become narrower after the native slice exists.

## Current Baseline

`cl-py` currently has two kinds of assets:

- Four existing Python-backed compatibility adapters: `packaging`, `python-dateutil`,
  `python-slugify`, and `jsonschema`
- A curated Common Lisp ecosystem catalog that identifies credible native libraries for HTTP, URI
  handling, HTML generation, database access, JSON, concurrency, CLI work, and time handling
- Native Common Lisp capability slices for JSON, time normalization, URI/HTTP work, CLI ergonomics,
  local registry snapshot persistence, and bounded task execution

The roadmap below shifts new feature work toward native Common Lisp modules while keeping the
existing adapter discipline available for explicit exception cases.

## Priority Tiers

| Priority | Native CL capability | Candidate libraries | Why it fits now | Suggested first slice |
| --- | --- | --- | --- | --- |
| P1 | JSON foundation | `jzon`, `shasht` | The project already exchanges JSON across adapter boundaries; owning a native JSON layer reduces incidental dependence on foreign tools. | Add a native JSON utility layer for parse, emit, and normalization helpers used by CLI and tests. |
| P1 | Time normalization | `local-time` | The repo already exposes datetime handling through `python-dateutil`; a native layer is the clearest way to reclaim core time logic. | Parse and format ISO-8601 timestamps in native Common Lisp with stable timezone handling. |
| P1 | URI and HTTP primitives | `quri`, `dexador` | External-system work needs reliable URI composition and HTTP fetch capability, including future catalog refresh automation. | Add URI normalization plus a small HTTP fetch helper for text and JSON responses. |
| P2 | CLI ergonomics | `clingon` | The current script interface works, but a richer native CLI will make the project more usable without changing the core architecture. | Replace ad hoc command parsing with structured subcommands, generated help, and option validation. |
| P2 | Data and query layer | `cl-dbi`, `sxql`, `mito` | Catalog and manifest data will eventually benefit from persistence and query composition; native database tooling is already strong. | Introduce a small persistence abstraction for catalog snapshots or manifest metadata. |
| P2 | Concurrency utilities | `lparallel`, `sento` | Network-backed catalog refreshes and future validation jobs are easier to scale once concurrency primitives are available natively. | Add a bounded task runner for parallel metadata refresh and batch validation jobs. |

## Recommended Build Order

1. Native JSON foundation
2. Native time normalization
3. Native URI and HTTP primitives
4. CLI ergonomics
5. Data and query layer
6. Concurrency utilities

The current repository has now completed a first concurrency slice through a native bounded task
runner. The next recommended work is the broader data/query layer beyond snapshot storage.

This order is intentional:

- JSON support strengthens the project's internal data model immediately.
- Time normalization reclaims a user-visible capability that is currently demonstrated through an
  external adapter.
- URI and HTTP support enable future automated catalog refresh work with native Common Lisp code.
- CLI improvements become more valuable after the command surface expands.
- Persistence and concurrency are easier to design once the foundational data and network paths are
  stable.

## Phased Backlog

This backlog translates the roadmap into implementation-sized changes that align with the current
repository structure: native Common Lisp source, CLI exposure, smoke coverage, and documentation in
one change.

### P1: Native JSON Foundation

Phase 1 scope:

- Module area: `src/json/` or equivalent native utility layer
- Candidate libraries reviewed first: `jzon`, `shasht`
- First CLI commands: `json parse`, `json emit`, `json normalize`
- Common Lisp entrypoints: `parse-json`, `emit-json`, `normalize-json`
- Input contract: JSON string or Common Lisp value
- Output contract: normalized Common Lisp value or canonical JSON string

Phase 1 smoke slices:

- Parse a small object and array deterministically
- Emit stable JSON for a small property list or alist input
- Normalize values used by existing adapter smoke tests

Phase 2 candidates:

- Streaming parse helpers
- Better error reporting with source offsets
- Shared coercion helpers for adapter and native modules

Why first:

- It reduces duplicated data handling across the project.
- It gives later native and interop features a stable internal contract.

### P1: Native Time Normalization

Phase 1 scope:

- Candidate library reviewed first: `local-time`
- First CLI commands: `time parse-iso`, `time format-iso`
- Common Lisp entrypoints: `parse-iso-timestamp`, `format-iso-timestamp`
- Input contract: ISO-8601 string or timestamp value
- Output contract: normalized Common Lisp timestamp object and canonical ISO-8601 string

Phase 1 smoke slices:

- Parse UTC and offset timestamps consistently
- Round-trip a timestamp through parse and format
- Produce clear errors for invalid input

Phase 2 candidates:

- Duration helpers
- Comparison and range predicates
- Optional migration path for the current `dateutil` adapter demo

Why now:

- Time handling is already part of the public story, so this is a concrete native recovery step.

### P1: Native URI and HTTP Primitives

Phase 1 scope:

- Candidate libraries reviewed first: `quri`, `dexador`
- First CLI commands: `uri normalize`, `http fetch-text`, `http fetch-json`
- Common Lisp entrypoints: `normalize-uri`, `fetch-text`, `fetch-json`
- Input contract: URI string plus optional request metadata
- Output contract: normalized URI string, response body string, or parsed JSON value

Phase 1 smoke slices:

- Normalize and encode representative URIs correctly
- Fetch deterministic local or mock text content
- Surface HTTP status and transport failures clearly

Phase 2 candidates:

- Header helpers
- Timeout and retry policy
- Catalog refresh source integration

Why now:

- It directly supports the constitution's live-source catalog requirement without defaulting to
  Python-based fetch tooling.

### P2: CLI Ergonomics

Phase 1 scope:

- Candidate library reviewed first: `clingon`
- First improvement: structured subcommands mirroring current adapter and native capability groups
- Common Lisp entrypoints: CLI dispatch only; no new business logic should live in the command
  layer

Phase 1 smoke slices:

- Generated help text for top-level commands
- Option validation for a representative JSON or time command
- Exit codes that distinguish usage errors from runtime failures

Phase 2 candidates:

- Shell completion generation
- Machine-readable command help
- Shared error rendering policy

### P2: Data and Query Layer

Phase 1 scope:

- Candidate libraries reviewed first: `cl-dbi`, `sxql`, `mito`
- First use case: persist catalog refresh snapshots or manifest metadata without changing user API
- Common Lisp entrypoints: small repository-facing persistence functions only

Phase 1 smoke slices:

- Create a local schema for one metadata table
- Insert and query a small snapshot deterministically
- Keep storage optional and clearly isolated from the default in-memory flow

Phase 2 candidates:

- Migration support
- Query helpers for catalog freshness reports
- Optional reporting commands

Current status:

- A lightweight native persistence slice now exists for registry snapshots through the `store`
  command group and matching Lisp API.
- The store layer now also supports snapshot queries for latest snapshot lookup, summary output,
  snapshot diffs, adapter history, aggregate reports, filtered aggregate reports,
  exclusion filters, group-selected output, row sorting, row offsets, row limits,
  per-group sort overrides, per-group paging overrides, absolute-delta sorting, file export,
  per-result pagination metadata, aggregate report diffs, snapshot deletion, snapshot pruning,
  lifecycle dry-run previews, explicit force confirmation for destructive cleanup, and
  structured lifecycle audit metadata in cleanup responses, including batched and prefix-selected snapshot deletion.
- This does not replace the broader database-backed roadmap. It reduces risk by establishing local
  persistence contracts and snapshot query flows before introducing a heavier storage dependency.

### P2: Concurrency Utilities

Phase 1 scope:

- Candidate libraries reviewed first: `lparallel`, `sento`
- First use case: bounded parallel execution for metadata refresh and validation jobs
- Common Lisp entrypoints: queue or task-runner helpers, not framework-heavy orchestration

Phase 1 smoke slices:

- Run a small batch of deterministic jobs in parallel
- Preserve ordered result collection
- Surface per-job failures without losing the whole batch context

Phase 2 candidates:

- Cancellation and timeout support
- Actor-style refresh workers if the simpler task-runner model proves insufficient

Current status:

- A lightweight native bounded task runner now exists through `run-bounded-task-batch` and the
  `jobs` CLI group.
- The first slice preserves ordered results, enforces a concurrency cap, and captures per-task
  failures without aborting the full batch.

## Cross-Cutting Work

Every roadmap item should ship with the same repository-facing changes:

1. Native Common Lisp implementation in `src/`
2. Public package exports only when the capability is stable and intentional
3. CLI registration through the existing script entrypoint
4. Smoke coverage in `tests/smoke.lisp`
5. Documentation updates in `README.md` and the relevant guide under `docs/`
6. Native-library review notes recorded in the spec or plan before implementation
7. Clear separation between reusable core logic and any compatibility adapter code

## Interop Exception Lane

External adapters are still allowed, but only after a written exception review. A new interop
proposal should be considered only when all of the following are true:

1. A native Common Lisp option was surveyed first and found insufficient for the concrete use case.
2. The capability is materially useful to Common Lisp users right now.
3. The boundary can stay narrow, replaceable, and machine-testable.
4. The native roadmap would still benefit from the adapter rather than being displaced by it.

Examples that remain deprioritized until an exception is justified:

- Additional Python validation layers beyond the current `jsonschema` demo
- Python web or HTTP clients where `dexador` already covers the need
- Python template engines where `djula` and `spinneret` already provide strong native options
- Python ORM layers where `cl-dbi`, `sxql`, and `mito` already cover the core problem space

## Immediate Next Candidate

If only one roadmap item is implemented next, it should be the native JSON foundation.

Why:

- It improves the internal contract shared by native modules and existing adapters.
- It is small enough to deliver cleanly.
- It makes later time, HTTP, catalog, and validation work easier to test and compose.
- It gives `cl-py` a stronger story for typed data ingestion, not just schema checking.