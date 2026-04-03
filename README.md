# cl-py

cl-py is a Common Lisp-first project for building reusable Common Lisp capabilities and, only when
justified, exposing external tooling through explicit, reproducible adapter boundaries.

## Current Status

This repository currently contains:

- A project constitution and Speckit workflow templates
- A Common Lisp code skeleton with a manifest-driven adapter registry
- A native JSON foundation for parse, emit, and normalization workflows
- A native time normalization layer for ISO-8601 parsing and formatting
- A native URI normalization and HTTP text/JSON fetch layer
- A native registry snapshot store for optional local persistence
- A native bounded task runner for structured concurrent job execution
- A development CLI
- Demonstration adapters for the Python `packaging`, `python-dateutil`, `python-slugify`, and `jsonschema` libraries
- Python bootstrap scripts and a minimal CI workflow
- An initial curated Common Lisp ecosystem catalog backed by live public web sources

The current goal is not to hide Python. The goal is to keep the user-facing surface owned by
Common Lisp and use external dependencies only where a narrow compatibility boundary is genuinely
needed.

## Repository Layout

```text
cl-py/
├── cl-py.asd
├── cl-py-tests.asd
├── README.md
├── adapters/
│   └── manifests/
│       ├── dateutil.sexp
│       ├── jsonschema.sexp
│       ├── packaging.sexp
│       └── slugify.sexp
├── requirements/
│   └── adapters/
│       ├── dateutil.txt
│       ├── jsonschema.txt
│       ├── packaging.txt
│       └── slugify.txt
├── scripts/
│   ├── bootstrap-python.ps1
│   ├── bootstrap-python.sh
│   ├── dev-cli.lisp
│   └── run-tests.lisp
├── src/
│   ├── package.lisp
│   ├── conditions.lisp
│   ├── process.lisp
│   ├── json.lisp
│   ├── time.lisp
│   ├── uri-http.lisp
│   ├── yaml.lisp
│   ├── manifest.lisp
│   ├── registry.lisp
│   ├── adapter.lisp
│   ├── cli-util.lisp
│   ├── cli.lisp
│   └── adapters/
│       ├── dateutil.lisp
│       ├── jsonschema.lisp
│       ├── packaging.lisp
│       └── slugify.lisp
└── tests/
    └── smoke.lisp
```

## Requirements

- Common Lisp implementation: SBCL first
- ASDF available
- Quicklisp optional but recommended for interactive local development
- Python 3 available on `PATH` or via `CL_PY_PYTHON`
- For the current demo adapters: Python packages `packaging`, `python-dateutil`, `python-slugify`, and `jsonschema`

Install the demo Python dependency with:

```bash
python -m pip install packaging
python -m pip install python-dateutil
python -m pip install python-slugify
python -m pip install jsonschema
```

Or bootstrap the local adapter environment with:

```bash
powershell -ExecutionPolicy Bypass -File scripts/bootstrap-python.ps1
# or
sh scripts/bootstrap-python.sh
```

## Documentation

- [Quickstart](docs/quickstart.md)
- [Development Guide](docs/development.md)
- [Ecosystem Catalog](docs/ecosystem-catalog.md)
- [Native Capability Roadmap](docs/adapter-roadmap.md)

## Development CLI

Run the development CLI with SBCL:

```bash
sbcl --script scripts/dev-cli.lisp help
sbcl --script scripts/dev-cli.lisp help json
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
sbcl --script scripts/dev-cli.lisp yaml parse 'name: cl-py'
sbcl --script scripts/dev-cli.lisp yaml emit '(:object ("name" . "cl-py"))'
sbcl --script scripts/dev-cli.lisp yaml normalize 'active: true
name: cl-py'
sbcl --script scripts/dev-cli.lisp http fetch-text http://127.0.0.1:8080/
sbcl --script scripts/dev-cli.lisp http fetch-json http://127.0.0.1:8080/data
sbcl --script scripts/dev-cli.lisp store snapshot-registry
sbcl --script scripts/dev-cli.lisp store list-registry
sbcl --script scripts/dev-cli.lisp jobs demo-batch 2
```

Generate HTML using the native DSL:

```bash
sbcl --script scripts/dev-cli.lisp --eval '(cl-py:html-string (:html (:head (:title "Test")) (:body (:h1 "Hello"))))'
sbcl --script scripts/dev-cli.lisp --eval '(cl-py:html-string (:div :class "box" (:p "Content")))'
sbcl --script scripts/dev-cli.lisp --eval '(cl-py:html-string (:img :src "test.png"))'
```
sbcl --script scripts/dev-cli.lisp store inventory-registry --limit 5
sbcl --script scripts/dev-cli.lisp store inventory-registry --prefix nightly- --created-after 2026-03-29T12:00:00Z
sbcl --script scripts/dev-cli.lisp store inventory-registry --adapter-count-min 3 --sort adapter-count-desc
sbcl --script scripts/dev-cli.lisp store inventory-registry --sort adapter-count-desc --limit 5
sbcl --script scripts/dev-cli.lisp jobs demo-batch 2
sbcl --script scripts/dev-cli.lisp packaging metadata
sbcl --script scripts/dev-cli.lisp packaging normalize-version 1.0rc1
sbcl --script scripts/dev-cli.lisp dateutil metadata
sbcl --script scripts/dev-cli.lisp dateutil parse-isodatetime 2026-03-29T10:20:30+00:00
sbcl --script scripts/dev-cli.lisp slugify metadata
sbcl --script scripts/dev-cli.lisp slugify slugify-text "Hello Common Lisp"
sbcl --script scripts/dev-cli.lisp jsonschema metadata
sbcl --script scripts/dev-cli.lisp jsonschema validate-instance '{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}' '{"name":"cl-py"}'
```

If Python is not on `PATH`, set:

```bash
CL_PY_PYTHON=/path/to/python
```

For REPL-oriented workflows and ASDF loading examples, see [docs/quickstart.md](docs/quickstart.md).

For shell environments where inline quoting is awkward, the native JSON, time, URI, and HTTP
commands also accept `@path` to read input from a file, or `-` to read from standard input.

The CLI now distinguishes usage errors from runtime errors: invalid command shapes exit with code
`2`, while runtime or dependency failures exit with code `1`.

Global help now lists adapter commands by adapter group, and `help <command>` works for both
native command groups such as `json` and adapter groups such as `packaging`.

Native command help also includes input-form guidance and runnable examples, so `help json`,
`help time`, `help uri`, `help http`, `help store`, and `help jobs` can be used as command-local reference pages.

The native store layer persists registry snapshots under `.cl-py-store/registry/` by default.
Set `CL_PY_STORE_DIR` to redirect snapshot storage elsewhere.

The store query layer also includes a paged snapshot inventory through
`inventory-registry-snapshots` and `store inventory-registry [--prefix <text> ...] [--created-before <timestamp>] [--created-after <timestamp>] [--adapter-count-min <n>] [--adapter-count-max <n>] [--sort <created-at-desc|created-at-asc|snapshot-id-asc|snapshot-id-desc|adapter-count-asc|adapter-count-desc>] [--offset <n>] [--limit <n>]`,
returning per-snapshot `snapshot-id`, `created-at`, `adapter-count`, a `filters` object, a matched-set `summary` object, the applied `sort` mode, and shared pagination
metadata for browsing stored snapshots without loading full payloads.
That `summary` object includes layered counts for total store snapshots, selector-stage matches, adapter-count filtering fallout, and final matched rows, plus oldest/newest and smallest/largest snapshot ids, boundary row objects, timestamps, total adapter counts, adapter-count span, and adapter-count bounds for the full filtered result set before pagination.

For lifecycle cleanup responses, the recommended stable contract is now the structured `summary`,
`matched` including `matched.request`, and `audit` sub-objects; mirrored top-level count and
selector fields remain available only as compatibility aliases, delete audit metadata echoes
normalized selector request context, and prune now uses the same request-versus-resolution
structure for retained versus deleted snapshots, including audit-level kept/deleted partition
metadata for logging.

## Test Runner

Run the smoke tests with:

```bash
sbcl --script scripts/run-tests.lisp
```

The smoke suite verifies the registry and CLI surface. Python-backed integration tests are skipped
automatically if their dependencies are unavailable.

## Native JSON Foundation

The first native Common Lisp capability slice is a JSON foundation that does not depend on Python.

Current capabilities:

- Parse JSON text into JSON-compatible Common Lisp values
- Emit canonical JSON from Common Lisp values
- Normalize JSON strings into deterministic key-sorted output
- Accept CLI JSON input from inline text, `@file`, or standard input

## Native Time Normalization

The second native Common Lisp capability slice adds ISO-8601 timestamp parsing and formatting.

Current capabilities:

- Parse timestamps matching `YYYY-MM-DDTHH:MM:SSZ`
- Parse timestamps matching `YYYY-MM-DDTHH:MM:SS+HH:MM` and `-HH:MM`
- Format parsed timestamp values back to canonical ISO-8601 strings
- Reject invalid date and time components in pure Common Lisp

## Native URI And HTTP Primitives

The third native Common Lisp capability slice adds URI normalization plus a small HTTP fetch layer.

Current capabilities:

- Normalize `http://` URIs with lowercase hostnames and default-path handling
- Remove the default HTTP port from normalized output
- Fetch plain text over loopback or remote `http://` endpoints using SBCL sockets
- Fetch JSON over `http://` and parse it through the native JSON layer

Current constraints:

- HTTPS is not implemented yet
- The first transport slice targets SBCL because it uses native socket support

## Native YAML Foundation

The sixth native Common Lisp capability slice adds YAML parsing and emission.

Current capabilities:

- Parse YAML text into Common Lisp data structures (`:object` alists, vectors for arrays)
- Emit Lisp data structures as YAML text
- Normalize YAML strings through parse and re-emit
- Accept CLI YAML input from inline text, `@file`, or standard input
- Handle YAML comments, indentation, scalars, sequences, and mappings

## Native Registry Snapshot Store

The fourth native Common Lisp capability slice adds a small local persistence layer for registry
snapshots.

Current capabilities:

- Save the current adapter registry as a canonical JSON snapshot
- List saved registry snapshots from local storage
- Load a snapshot back into the native JSON data model
- Delete one or more saved registry snapshots by id with explicit force confirmation
- Select saved registry snapshots for deletion by prefix in the same lifecycle command
- Select saved registry snapshots for deletion by creation time threshold in the same lifecycle command
- Combine creation-time lower and upper bounds to delete snapshots within a time window
- Report before/after snapshot counts for delete and prune lifecycle operations
- Report selector match sources for delete lifecycle operations
- Report selector match counts for delete lifecycle operations
- Report a deduplicated total selector match count for mixed delete lifecycle operations
- Report a structured prune summary object for lifecycle cleanup automation
- Report a structured delete summary object for lifecycle cleanup automation
- Unify delete and prune lifecycle summaries around a shared `affected-count` field
- Unify delete and prune lifecycle summaries around shared `affected-count` and `affected-snapshot-ids` fields
- Make lifecycle `summary` the canonical source for count fields while retaining mirrored top-level counts for compatibility
- Prune older registry snapshots while keeping the newest N ids with explicit force confirmation
- Preview delete and prune lifecycle operations with dry-run mode before changing disk state
- Emit structured lifecycle audit metadata for delete and prune operations
- Query the latest, summarized, and diffed view of stored snapshots
- Query per-adapter history across stored snapshots
- Build aggregate snapshot reports grouped by license and capability
- Filter aggregate reports by license or capability before counting
- Compare aggregate report deltas between two snapshots
- Combine multiple `--license` or `--capability` filters in the same report query
- Restrict aggregate output to license rows or capability rows when needed
- Sort license rows and capability rows independently when needed
- Sort aggregate report rows by count and diff rows by delta
- Exclude licenses or capabilities from report and diff-report queries
- Limit report and diff-report result rows after sorting
- Override license and capability paging independently when both groups are returned
- Sort diff-report rows by absolute delta magnitude
- Page sorted report rows with offsets before applying limits
- Return per-result pagination metadata for aggregate and diff rows
- Export report and diff-report JSON directly to files from the CLI
- Redirect snapshot storage with `CL_PY_STORE_DIR`

## Native Concurrency Utilities

The fifth native Common Lisp capability slice adds a bounded task runner for structured concurrent
work.

Current capabilities:

- Run a list of zero-argument task functions with a max-concurrency bound
- Preserve input order in the returned result list
- Capture per-task failures as structured results instead of aborting the full batch
- Demonstrate the runner through the `jobs demo-batch` CLI command

## Native HTML Generation DSL

The sixth native Common Lisp capability slice adds a spinneret-inspired HTML generation DSL.

Current capabilities:

- Generate HTML from S-expression syntax with zero external dependencies
- 50+ HTML5 element macros (html, head, body, div, span, table, form, etc.)
- Automatic HTML escaping for content and attributes
- Indentation-tracking output for pretty-printed HTML
- `html-string`, `html-file`, and `with-html-output` macros
- Self-closing tag support for br, hr, img, input, meta, link, etc.
- Semantic HTML5 element support (header, footer, nav, main, article, section, aside, etc.)
- Integration with store module via `report-registry-to-html`

## First Adapter: packaging

The first adapter targets the Python `packaging` project because it is:

- High quality and broadly used
- Small enough to demonstrate the adapter boundary cleanly
- Useful for version normalization and compatibility work inside a wider adapter registry

Current capabilities:

- Discover adapter metadata
- Discover installed upstream module version
- Normalize a version string through `packaging.version.Version`

## Second Adapter: python-dateutil

The second adapter targets `python-dateutil` because it adds a common real-world data boundary:
parsing structured datetimes from Python without forcing Python implementation details into the
Common Lisp public API.

Current capabilities:

- Discover adapter metadata
- Discover installed upstream distribution version
- Parse ISO datetime strings through `dateutil.parser.isoparse`

## Third Adapter: python-slugify

The third adapter targets `python-slugify` because it is a compact but realistic example of text
normalization that many Common Lisp applications need for URLs, identifiers, or content pipelines.

Current capabilities:

- Discover adapter metadata
- Discover installed upstream distribution version
- Convert text to a URL-friendly slug via `slugify.slugify`

## Fourth Adapter: jsonschema

The fourth adapter targets `jsonschema` because it adds structured data validation to the adapter
set and exercises a realistic multi-argument command surface.

Current capabilities:

- Discover adapter metadata
- Discover installed upstream distribution version
- Validate a JSON instance against a JSON Schema

## Adapter Manifests

Adapter discovery is now manifest-driven. Each adapter gets a manifest in
[adapters/manifests/packaging.sexp](adapters/manifests/packaging.sexp) that declares:

- Adapter id and name
- Upstream Python module
- Upstream Python distribution name
- Supported capabilities
- License metadata
- Python requirement range
- Upstream project URL

The Common Lisp registry loads these manifests at system startup.

CLI dispatch is now generic: every adapter gets built-in `metadata` and `version` commands, while
adapter-specific commands are registered from the adapter implementation layer.

## CI

GitHub Actions now installs Python, SBCL, the adapter requirements, and runs the smoke suite on
push and pull request events.

## Next Steps

- Implement the next native Common Lisp capabilities from [docs/adapter-roadmap.md](docs/adapter-roadmap.md)
- Expand the Common Lisp ecosystem catalog with more categories and refresh passes
- Expand CI to exercise richer adapter compatibility contracts
- Add manifest validation and richer adapter contract tests
