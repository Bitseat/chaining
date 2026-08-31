#!/usr/bin/env python3
"""Bridge between the MeTTa proof-search harness and the WILLIAM/infcontrol premise selector.

The harness calls :func:`score` once per theorem with the goal and the whole
candidate pool; it gets back one probability per candidate, in the same order,
and does the ranking and top-N truncation itself in MeTTa.

Why scores and not labels: PeTTa's py-call marshals a Python list of floats
cleanly (metta-attention already relies on that in getelement.py), whereas a
list of strings comes back as strings rather than symbols and no longer
matches `(: LABEL TYPE)` in the rule base.  Keeping label handling on the
MeTTa side avoids that entirely.

FORMULA FORMAT.  infcontrol identifies variables by their FIRST CHARACTER
being Greek (see infcontrol/canonicalize.py), then renames them v0, v1, ...
in first-occurrence order.  So the formulas handed over here must be the
ORIGINAL corpus statements, which spell variables as 𝜑, 𝜓, 𝜒 ... — not the
knowledge-base copies, where replace-greeks-by-variables has already turned
them into MeTTa variables that repr as `$_3322`.  A `$_3322` would be treated
as a constant symbol and every shared-variable feature would be wrong.
All twelve variables used by this corpus are in infcontrol's GREEK_CHARS.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


# --------------------------------------------------------------------------
# S-expression parsing (the harness hands us `repr` output)
# --------------------------------------------------------------------------

def _tokenize(text: str):
    token = ""
    for c in text:
        if c in "()":
            if token:
                yield token
                token = ""
            yield c
        elif c.isspace():
            if token:
                yield token
                token = ""
        else:
            token += c
    if token:
        yield token


def parse_sexpr(text: str):
    """Parse one s-expression into nested lists. Bare atoms stay strings."""
    stack, current = [], None
    for tok in _tokenize(text):
        if tok == "(":
            new = []
            if current is not None:
                stack.append(current)
            current = new
        elif tok == ")":
            if stack:
                finished = current
                current = stack.pop()
                current.append(finished)
            else:
                return current
        else:
            if current is None:
                return tok
            current.append(tok)
    return current


# --------------------------------------------------------------------------
# The predictor runs in its own virtualenv, as a subprocess
# --------------------------------------------------------------------------
#
# PeTTa's py-call executes in the SYSTEM python, which cannot see the venv
# william/infcontrol are installed into.  So instead of importing infcontrol
# here, we spawn infcontrol's own predict_cli service in the venv and talk
# newline-delimited JSON to it -- the integration path its README documents.
# Nothing in this module needs a third-party package.

_PROC = None
_MODEL_DIR_ENV = "INFCONTROL_MODEL_DIR"
_PYTHON_ENV = "WILLIAM_PYTHON"
_HERE = Path(__file__).resolve().parent
_MODEL_SEARCH = (
    _HERE / "models" / "default",
    _HERE / "repos" / "infcontrol" / "models" / "model01",
)
_DEFAULT_PYTHON = _HERE.parents[2] / ".venv-william" / "bin" / "python"


def model_dir() -> Path:
    """INFCONTROL_MODEL_DIR if set, else the first model directory that exists."""
    override = os.environ.get(_MODEL_DIR_ENV)
    if override:
        return Path(override)
    for candidate in _MODEL_SEARCH:
        if candidate.is_dir():
            return candidate
    return _MODEL_SEARCH[0]


def python_bin() -> Path:
    return Path(os.environ.get(_PYTHON_ENV, _DEFAULT_PYTHON))


def _service():
    """Start (once) infcontrol.predict_cli in the venv and keep it warm."""
    global _PROC
    if _PROC is not None and _PROC.poll() is None:
        return _PROC

    python = python_bin()
    directory = model_dir()
    if not python.exists():
        raise FileNotFoundError(
            f"No venv python at {python}. Create it with:\n"
            f"  python3 -m venv .venv-william && .venv-william/bin/pip install william packaging\n"
            f"  .venv-william/bin/pip install -e experimental/metamath-aa/pc-xp-william/repos/infcontrol\n"
            f"or point {_PYTHON_ENV} at a python that has william + infcontrol."
        )
    if not directory.is_dir():
        raise FileNotFoundError(
            f"No infcontrol model at {directory}.\n"
            f"infcontrol gitignores models/, so the trained model is NOT in the clone --\n"
            f"ask Arthur for the model directory, put it there, or point {_MODEL_DIR_ENV} at it."
        )

    _PROC = subprocess.Popen(
        [str(python), "-m", "infcontrol.predict_cli", "--model-dir", str(directory)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1,
    )
    return _PROC


def _ask(request: dict):
    proc = _service()
    proc.stdin.write(json.dumps(request) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        stderr = proc.stderr.read() if proc.stderr else ""
        raise RuntimeError(f"predict_cli died: {stderr.strip()[:500]}")
    response = json.loads(line)
    if "error" in response:
        raise RuntimeError(f"predict_cli error: {response['error']}")
    return response


# --------------------------------------------------------------------------
# The entry points the harness calls
# --------------------------------------------------------------------------

def score(goal_sexpr: str, pairs_sexpr: str):
    """Probability that each candidate is used in a proof of the goal.

    goal_sexpr  : the goal statement,   e.g. "(-> (\u2192 \U0001d711 \U0001d713) \U0001d711 \U0001d713)"
    pairs_sexpr : the candidate pool as "((P label stmt) (P label stmt) ...)"
    returns     : list[float], one per candidate, in the given order
    """
    goal = parse_sexpr(goal_sexpr)
    pairs = parse_sexpr(pairs_sexpr) or []
    candidates = [p[2] for p in pairs]
    if not candidates:
        return []
    # One batched request for the whole pool: ~180 candidates per theorem over
    # ~176 theorems is ~32k pairs per run, far too many to ask for one at a time.
    response = _ask({"goals": [goal] * len(candidates), "candidates": candidates})
    return [float(x) for x in response["probabilities"]]


def dry_score(goal_sexpr: str, pairs_sexpr: str):
    """Same shape as `score`, but no model: every candidate gets 0.0.

    Lets the MeTTa plumbing (repr -> py-call -> list of floats) be exercised
    end to end before the trained model is available.  The resulting focus is
    arbitrary, so this is a wiring test, never a measurement.
    """
    return [0.0] * len(parse_sexpr(pairs_sexpr) or [])


def labels(pairs_sexpr: str):
    """Candidate labels, in the same order `score` returns probabilities."""
    return [p[1] for p in (parse_sexpr(pairs_sexpr) or [])]


# --------------------------------------------------------------------------
# Self-test / CLI
# --------------------------------------------------------------------------

GREEK = set("αβγδεζηθικλμνξοπρστυφχψω𝛼𝛽𝛾𝛿𝜀𝜁𝜂𝜃𝜄𝜅𝜆𝜇𝜈𝜉𝜊𝜋𝜌𝜎𝜏𝜐𝜑𝜒𝜓𝜔")


def _canonicalize_preview(node, mapping=None):
    """Mirror of infcontrol.canonicalize, for the self-test only."""
    mapping = {} if mapping is None else mapping
    if isinstance(node, list):
        return [_canonicalize_preview(x, mapping) for x in node]
    if isinstance(node, str) and node and node[0] in GREEK:
        mapping.setdefault(node, f"v{len(mapping)}")
        return mapping[node]
    return node


def selftest() -> int:
    goal = "(-> (→ 𝜑 𝜓) 𝜑 𝜓)"
    pairs = "((P ax-1 (→ 𝜑 (→ 𝜓 𝜑))) (P ax-mp (-> (→ 𝜑 𝜓) 𝜑 𝜓)) (P id (-> 𝜑 𝜑)))"

    print("1. s-expression parsing")
    g, p = parse_sexpr(goal), parse_sexpr(pairs)
    print("   goal      ->", json.dumps(g, ensure_ascii=False))
    print("   candidate ->", json.dumps(p[1][2], ensure_ascii=False))
    print("   labels    ->", labels(pairs))

    print("2. variable canonicalisation (must yield v0/v1, not constants)")
    canonical = _canonicalize_preview(g)
    print("   canonical ->", json.dumps(canonical, ensure_ascii=False))
    if "v0" not in json.dumps(canonical):
        print("   FAIL: no v0 produced -- variables were not recognised")
        return 1

    print("3. predictor service")
    try:
        probabilities = score(goal, pairs)
    except Exception as exc:  # noqa: BLE001 - this is the reporting path
        print(f"   NOT AVAILABLE: {exc}")
        print("\nParsing and canonicalisation are correct; only the model is missing.")
        return 2
    for label, probability in zip(labels(pairs), probabilities):
        print(f"   {label:10s} {probability:.6g}")
    print("\nAll good.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        raise SystemExit(selftest())
    request = json.loads(sys.stdin.read())
    json.dump(score(request["goal"], request["pairs"]), sys.stdout)
