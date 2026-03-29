<!--
Sync Impact Report
Version change: 1.1.0 -> 2.0.0
Modified principles:
- I. Common Lisp Core
- II. Explicit Python Adapter Boundary -> II. External Interop Is Exceptional
- III. Curated Open Source Intake and Ecosystem Intelligence -> III. Common Lisp-First Open Source Intake and Ecosystem Intelligence
Added sections:
- Native-first implementation requirement
- Written exception policy for external interop
Removed sections:
- Default assumption that Python library exposure is the project's primary growth path
Templates requiring updates:
- ✅ .specify/templates/plan-template.md
- ✅ .specify/templates/spec-template.md
- ✅ .specify/templates/tasks-template.md
Follow-up TODOs:
- Align roadmap and repository docs to native Common Lisp-first planning
-->

# cl-py Constitution

## Core Principles

### I. Common Lisp Core
All product-facing logic MUST be authored in Common Lisp. Package discovery, API design,
orchestration, data normalization, documentation generation, and user-visible behavior MUST live
in Common Lisp source owned by this repository. If a capability can be implemented with reasonable
quality directly in Common Lisp, that Common Lisp implementation MUST be preferred over wrapping a
foreign implementation. External code MAY support migration, comparison, or compatibility edges,
but foreign implementations MUST NOT become the canonical home of project logic. This keeps the
project genuinely usable from Common Lisp rather than acting as a thin rebrand of other tooling.

### II. External Interop Is Exceptional
External language interop is allowed only as an explicit exception, never as the default growth
strategy for the repository. Any Python or other foreign-language integration MUST justify why a
native Common Lisp implementation is currently insufficient, what user need cannot yet be met in
pure Common Lisp, and how the foreign boundary will remain replaceable. Each exception MUST define
the exported capability, input and output schema, failure modes, version policy, and an exit or
replacement path back toward Common Lisp ownership. Process or protocol boundaries are preferred;
embedding language runtimes or implementation-specific FFI requires written justification in the
feature plan.

### III. Common Lisp-First Open Source Intake and Ecosystem Intelligence
The project exists first to strengthen the Common Lisp ecosystem and only secondarily to bridge to
external ecosystems when a clear gap remains. Native Common Lisp libraries, frameworks, and tools
MUST be surveyed before any foreign interop proposal is approved. A foreign library MAY be added
only if it is actively maintained or clearly stable, license-compatible with the repository, well
documented, meaningfully useful to Common Lisp users, and not reasonably replaceable by an
available Common Lisp option for the same use case. Each adoption decision MUST record the native
Common Lisp alternatives considered, the reason they were not selected, the upstream project name,
purpose, license, maintenance signal, and version policy. The repository MUST also maintain a
curated Common Lisp ecosystem catalog based on live network-sourced information whenever external
access is available. Catalog entries MUST include, at minimum, library name, canonical access or
download link, concise description, last observed upstream update date, and the date on which this
repository refreshed the entry.

### IV. Reproducible Compatibility Gates
Every adapter MUST ship with automated verification that proves the Common Lisp surface works
against the declared Python dependency set. At minimum this includes smoke tests for the adapter
contract, deterministic environment setup, and examples that can be executed in CI. New work MUST
prefer repeatable machine-readable outputs, pinned dependency ranges, and failure messages that
allow users to diagnose whether a problem comes from Common Lisp code, Python dependencies, or the
interop boundary.

### V. Small, Composable Deliveries
The repository MUST grow through small, composable Common Lisp capabilities and shared
infrastructure rather than one monolithic universal bridge. Each feature SHOULD add a bounded
capability slice: one native Common Lisp library component, one registry improvement, one
packaging improvement, one ecosystem intelligence improvement, or one narrowly justified
compatibility layer. Complex abstractions are allowed only after at least one concrete need is
demonstrated. When a simpler native Common Lisp design can satisfy the current use case, the
simpler design wins.

## Architecture and Compatibility Constraints

- The reference implementation MUST target ANSI Common Lisp with SBCL as the first supported
	runtime.
- Design decisions SHOULD avoid unnecessarily locking the project out of other Common Lisp
	implementations; implementation-specific code MUST be isolated and documented.
- Any external interop spec MUST identify the target runtime version range, installation strategy,
	and native Common Lisp alternative review.
- Interop protocols SHOULD prefer plain data exchange formats such as JSON, line-oriented text, or
	other documented schemas before reaching for bespoke binary bindings.
- Vendoring third-party non-Common-Lisp code into this repository requires an explicit legal and
	maintenance justification.
- Public APIs MUST remain stable at the Common Lisp layer even if an underlying external tool is
	upgraded, swapped, or removed.

## Delivery Workflow and Quality Gates

- Every specification MUST state the user-facing Common Lisp capability, native Common Lisp design
	approach, any external dependency exceptions, license expectations, and out-of-scope boundaries.
- Every implementation plan MUST pass a constitution check covering Common Lisp core ownership,
	native-first design, exception justification for external interop, upstream quality review,
	license compatibility, and reproducibility.
- Any feature or maintenance task that curates Common Lisp ecosystem knowledge MUST identify the
	public network sources used, define refresh expectations, and specify the output schema for the
	catalog entries.
- Every task list MUST include work for native Common Lisp implementation, runtime validation, and
	documentation or examples. When an approved external interop exception is in scope, tasks MUST
	also include boundary contract definition, environment setup, compatibility testing, and failure
	surfacing. When ecosystem catalog work is in scope, tasks MUST include source retrieval,
	normalization, and refresh-date recording.
- Every merge request MUST show how the feature is exercised from Common Lisp and how dependency
	failures are surfaced to users.
- Breaking changes to public Common Lisp interfaces or approved external interop contracts MUST
	include a migration note and version bump rationale.

## Governance

This constitution overrides conflicting local conventions, generated templates, and feature-level
preferences. Compliance MUST be checked during specification, planning, review, and release.

Amendments require a documented rationale, an explicit description of affected principles or
sections, and any template updates needed to keep generated artifacts aligned. Versioning follows
semantic rules for governance: MAJOR for incompatible principle changes or removals, MINOR for new
principles or materially expanded requirements, and PATCH for clarifications that do not change
expected behavior.

Reviewers MUST reject changes that violate the Common Lisp core boundary, skip native-option
evaluation, omit upstream license or quality evaluation, or skip reproducibility gates without an
approved exception recorded in the plan. Exceptions MUST be narrow, time-bounded, and tracked to
removal.

**Version**: 2.0.0 | **Ratified**: 2026-03-29 | **Last Amended**: 2026-03-29
