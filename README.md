# cl-py

cl-py is a Common Lisp-first project for exposing high-quality Python open source libraries to
Common Lisp users through explicit, reproducible adapter boundaries.

## Current Status

This repository currently contains:

- A project constitution and Speckit workflow templates
- A Common Lisp code skeleton with a manifest-driven adapter registry
- A development CLI
- Demonstration adapters for the Python `packaging` and `python-dateutil` libraries
- Python bootstrap scripts and a minimal CI workflow

The current goal is not to hide Python. The goal is to make Python dependencies consumable from a
stable Common Lisp surface.

## Repository Layout

```text
cl-py/
├── cl-py.asd
├── cl-py-tests.asd
├── README.md
├── adapters/
│   └── manifests/
│       ├── dateutil.sexp
│       └── packaging.sexp
├── requirements/
│   └── adapters/
│       ├── dateutil.txt
│       └── packaging.txt
├── scripts/
│   ├── bootstrap-python.ps1
│   ├── bootstrap-python.sh
│   ├── dev-cli.lisp
│   └── run-tests.lisp
├── src/
│   ├── package.lisp
│   ├── conditions.lisp
│   ├── process.lisp
│   ├── manifest.lisp
│   ├── registry.lisp
│   ├── adapter.lisp
│   ├── cli.lisp
│   └── adapters/
│       ├── dateutil.lisp
│       └── packaging.lisp
└── tests/
    └── smoke.lisp
```

## Requirements

- Common Lisp implementation: SBCL first
- ASDF available
- Quicklisp optional but recommended for interactive local development
- Python 3 available on `PATH` or via `CL_PY_PYTHON`
- For the current demo adapters: Python packages `packaging` and `python-dateutil`

Install the demo Python dependency with:

```bash
python -m pip install packaging
python -m pip install python-dateutil
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

## Development CLI

Run the development CLI with SBCL:

```bash
sbcl --script scripts/dev-cli.lisp registry
sbcl --script scripts/dev-cli.lisp packaging metadata
sbcl --script scripts/dev-cli.lisp packaging normalize-version 1.0rc1
sbcl --script scripts/dev-cli.lisp dateutil metadata
sbcl --script scripts/dev-cli.lisp dateutil parse-isodatetime 2026-03-29T10:20:30+00:00
```

If Python is not on `PATH`, set:

```bash
CL_PY_PYTHON=/path/to/python
```

For REPL-oriented workflows and ASDF loading examples, see [docs/quickstart.md](docs/quickstart.md).

## Test Runner

Run the smoke tests with:

```bash
sbcl --script scripts/run-tests.lisp
```

The smoke suite verifies the registry and CLI surface. Python-backed integration tests are skipped
automatically if their dependencies are unavailable.

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

## CI

GitHub Actions now installs Python, SBCL, the adapter requirements, and runs the smoke suite on
push and pull request events.

## Next Steps

- Add more adapters for selected Python libraries
- Expand CI to exercise richer adapter compatibility contracts
- Add manifest validation and richer adapter contract tests
