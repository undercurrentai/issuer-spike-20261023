#!/bin/sh
# Stage "tests-junit-coverage" (stage-spec-draft.yaml). POSIX sh; runs in the container or natively.
# usage: run_stage.sh install|test PY SRC DEPS OUT SPEC
set -eu
phase=$1 PY=$2 SRC=$3 DEPS=$4 OUT=$5 SPEC=$6
case "$phase" in
install)
  # Network allowed in this phase only. Hash-locked wheels only; no sdists; no subject index config.
  env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp PIP_CONFIG_FILE=/dev/null \
    "$PY" -m pip install --isolated --no-deps --require-hashes --only-binary=:all: \
    --no-compile --disable-pip-version-check --no-cache-dir --quiet \
    --target "$DEPS" -r "$SPEC/requirements.lock"
  ;;
test)
  # Empty environment: only the variables listed in the stage spec. No network (set by the runner).
  mkdir -p "$OUT/raw"
  cd "$SRC"
  set +e
  env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp TZ=UTC LC_ALL=C.UTF-8 \
    PYTHONPATH="$DEPS:$SRC/src" PYTHONDONTWRITEBYTECODE=1 PYTHONHASHSEED=0 \
    PYTHONNOUSERSITE=1 COVERAGE_FILE="$OUT/raw/.coverage" COVERAGE_CORE=ctrace \
    "$PY" -m pytest -p no:cacheprovider --rootdir="$SRC" \
      -o junit_family=xunit2 -o junit_logging=no -o junit_duration_report=total \
      --junitxml="$OUT/raw/junit.xml" \
      --cov --cov-config="$SPEC/coveragerc" --cov-report=json:"$OUT/raw/coverage.json" --cov-report= \
      -q tests > "$OUT/raw/pytest-stdout.txt" 2>&1
  rc=$?
  set -e
  echo "$rc" > "$OUT/raw/exit-code"
  "$PY" -I "$SPEC/normalize.py" "$OUT" "$SRC" "$DEPS" "$OUT" > "$OUT/normalize-stdout.json"
  ;;
*) echo "unknown phase $phase" >&2; exit 2 ;;
esac
