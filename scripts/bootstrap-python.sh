#!/usr/bin/env sh
set -eu

PYTHON_BIN="${CL_PY_BOOTSTRAP_PYTHON:-python3}"
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VENV_PATH="$REPO_ROOT/.venv"
REQ_DIR="$REPO_ROOT/requirements/adapters"

if [ ! -d "$VENV_PATH" ]; then
  "$PYTHON_BIN" -m venv "$VENV_PATH"
fi

"$VENV_PATH/bin/python" -m pip install --upgrade pip

for req in "$REQ_DIR"/*.txt; do
  "$VENV_PATH/bin/python" -m pip install -r "$req"
done

echo "Python adapter environment is ready at .venv"
