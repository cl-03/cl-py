<!--
Sync Impact Report
Version change: 1.0.0 -> 1.1.0
Modified principles:
- III. Curated Open Source Intake -> III. Curated Open Source Intake and Ecosystem Intelligence
Added sections:
- Network-backed Common Lisp Ecosystem Catalog requirement in workflow gates
Removed sections:
- None
Templates requiring updates:
- ✅ .specify/templates/plan-template.md
- ✅ .specify/templates/spec-template.md
- ✅ .specify/templates/tasks-template.md
Follow-up TODOs:
- None
-->

# cl-py Constitution

## Core Principles

### I. Common Lisp Core
All product-facing logic MUST be authored in Common Lisp. Package discovery, API design,
orchestration, data normalization, documentation generation, and user-visible behavior MUST live
in Common Lisp source owned by this repository. Python code MAY be invoked as an external
dependency adapter, but Python implementations MUST NOT become the canonical home of project
logic. This keeps the project genuinely usable from Common Lisp rather than acting as a thin
rebrand of Python tooling.

### II. Explicit Python Adapter Boundary
Every Python library integration MUST be exposed through an explicit adapter contract owned by
this repository. Each adapter MUST declare supported Python package versions, exported
capabilities, input and output schema, failure modes, and fallback behavior. The default
integration mode SHOULD be process or protocol boundaries that preserve a pure Common Lisp core;
embedding CPython or using implementation-specific FFI requires a written justification in the
feature plan.

### III. Curated Open Source Intake and Ecosystem Intelligence
The project exists to make high-quality Python open source libraries available to Common Lisp,
not to mirror the entire Python ecosystem indiscriminately. A library MAY be added only if it is
actively maintained or clearly stable, license-compatible with the repository, well documented,
and meaningfully useful to Common Lisp users. Each adoption decision MUST record the upstream
project name, purpose, license, maintenance signal, version policy, and the reason it was chosen
over competing libraries. The repository MUST also maintain a curated Common Lisp ecosystem catalog
based on live network-sourced information whenever external access is available. Catalog entries
MUST include, at minimum, library name, canonical access or download link, concise description,
last observed upstream update date, and the date on which this repository refreshed the entry.

### IV. Reproducible Compatibility Gates
Every adapter MUST ship with automated verification that proves the Common Lisp surface works
against the declared Python dependency set. At minimum this includes smoke tests for the adapter
contract, deterministic environment setup, and examples that can be executed in CI. New work MUST
prefer repeatable machine-readable outputs, pinned dependency ranges, and failure messages that
allow users to diagnose whether a problem comes from Common Lisp code, Python dependencies, or the
interop boundary.

### V. Small, Composable Deliveries
The repository MUST grow through small, composable wrappers and shared infrastructure rather than
one monolithic universal bridge. Each feature SHOULD add a bounded capability slice: one adapter,
one registry improvement, one packaging improvement, or one cross-cutting compatibility layer.
Complex abstractions are allowed only after at least one concrete adapter demonstrates the need.
When a simpler design can satisfy the current use case, the simpler design wins.

## Architecture and Compatibility Constraints

- The reference implementation MUST target ANSI Common Lisp with SBCL as the first supported
	runtime.
- Design decisions SHOULD avoid unnecessarily locking the project out of other Common Lisp
	implementations; implementation-specific code MUST be isolated and documented.
- Every adapter spec MUST identify the target Python version range and installation strategy.
- Interop protocols SHOULD prefer plain data exchange formats such as JSON, line-oriented text, or
	other documented schemas before reaching for bespoke binary bindings.
- Upstream Python packages MUST remain separately attributable; vendoring third-party Python code
	into this repository requires an explicit legal and maintenance justification.
- Public APIs MUST remain stable at the Common Lisp layer even if the underlying Python library is
	upgraded or swapped.

## Delivery Workflow and Quality Gates

- Every specification MUST state the user-facing Common Lisp capability, target upstream Python
	library or library class, license expectations, and out-of-scope boundaries.
- Every implementation plan MUST pass a constitution check covering Common Lisp core ownership,
	adapter boundary choice, upstream library quality, license compatibility, and reproducibility.
- Any feature or maintenance task that curates Common Lisp ecosystem knowledge MUST identify the
	public network sources used, define refresh expectations, and specify the output schema for the
	catalog entries.
- Every task list MUST include work for adapter contract definition, environment setup,
	compatibility testing, and documentation or examples. When ecosystem catalog work is in scope,
	tasks MUST include source retrieval, normalization, and refresh-date recording.
- Every merge request MUST show how the feature is exercised from Common Lisp and how dependency
	failures are surfaced to users.
- Breaking changes to public Common Lisp interfaces or supported adapter contracts MUST include a
	migration note and version bump rationale.

## Governance

This constitution overrides conflicting local conventions, generated templates, and feature-level
preferences. Compliance MUST be checked during specification, planning, review, and release.

Amendments require a documented rationale, an explicit description of affected principles or
sections, and any template updates needed to keep generated artifacts aligned. Versioning follows
semantic rules for governance: MAJOR for incompatible principle changes or removals, MINOR for new
principles or materially expanded requirements, and PATCH for clarifications that do not change
expected behavior.

Reviewers MUST reject changes that violate the Common Lisp core boundary, omit upstream license or
quality evaluation, or skip reproducibility gates without an approved exception recorded in the
plan. Exceptions MUST be narrow, time-bounded, and tracked to removal.

**Version**: 1.1.0 | **Ratified**: 2026-03-29 | **Last Amended**: 2026-03-29
