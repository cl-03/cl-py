# cl-py

cl-py is a Common Lisp-first project for building reusable Common Lisp capabilities and, only when
justified, exposing external tooling through explicit, reproducible adapter boundaries.

## Current Status

This repository currently contains:

- A project constitution and Speckit workflow templates
- A Common Lisp code skeleton with a manifest-driven adapter registry
- A native JSON foundation for parse, emit, and normalization workflows
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
│   ├── manifest.lisp
│   ├── registry.lisp
│   ├── adapter.lisp
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
sbcl --script scripts/dev-cli.lisp registry
sbcl --script scripts/dev-cli.lisp json parse '{"name":"cl-py","active":true}'
sbcl --script scripts/dev-cli.lisp json emit '(("name" . "cl-py") ("active" . :true))'
sbcl --script scripts/dev-cli.lisp json normalize '{"b":2,"a":1}'
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

For shell environments where inline JSON quoting is awkward, the JSON commands also accept `@path`
to read input from a file, or `-` to read from standard input.

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
