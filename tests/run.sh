#!/bin/bash
# tests/run.sh - fixture tests for the lib/diagnose.sh verdicts.
# No NVIDIA hardware needed: dkms/lspci are shadowed by exported functions
# printing fixture files, then gpu_diagnose runs in a child shell.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
PASS=0
FAIL=0
for d in "$HERE"/fixtures/*.dkms.txt; do
  case_name="$(basename "$d" .dkms.txt)"
  export case_name HERE
  dkms() { cat "$HERE/fixtures/$case_name.dkms.txt"; }
  lspci() { cat "$HERE/fixtures/$case_name.lspci.txt"; }
  export -f dkms lspci
  out="$(bash -c '. "$0"; gpu_diagnose' "$ROOT/lib/diagnose.sh")"
  want="$(cat "$HERE/fixtures/$case_name.expected")"
  if echo "$out" | grep -qF "$want"; then
    echo "PASS: $case_name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $case_name (want [$want], got:)"
    echo "$out"
    FAIL=$((FAIL + 1))
  fi
done
echo "---"
echo "tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
