#!/usr/bin/env python3
"""Normalize stage outputs per NORMALIZATION.md (N1-N3) and write digests.

usage: normalize.py OUT_DIR SRC_ROOT DEPS_ROOT OUT_ROOT
Reads OUT_DIR/raw/{junit.xml,coverage.json}; writes OUT_DIR/norm/* and OUT_DIR/digests.json.
Stdlib only.
"""
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

DROP_ATTRS = ("timestamp", "time", "hostname")
ADDR = re.compile(r"0x[0-9a-fA-F]{6,}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scrub(text, roots):
    if text is None:
        return None
    for root, token in roots:
        text = text.replace(root, token)
    return ADDR.sub("0x<ADDR>", text)


def norm_junit(src: Path, dst: Path, roots) -> dict:
    tree = ET.parse(src)
    top = tree.getroot()
    for el in top.iter():
        for a in DROP_ATTRS:
            el.attrib.pop(a, None)
        for k, v in list(el.attrib.items()):
            el.attrib[k] = scrub(v, roots)
        el.text = scrub(el.text, roots)
        el.tail = scrub(el.tail, roots)
    xml = ET.tostring(top, encoding="unicode")
    dst.write_bytes((ET.canonicalize(xml, strip_text=True) + "\n").encode("utf-8"))
    suite = top if top.tag == "testsuite" else top.find("testsuite")
    return {k: int(suite.get(k, "0")) for k in ("tests", "failures", "errors", "skipped")}


def dump(obj, dst: Path):
    dst.write_bytes(
        (json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")
    )


def norm_cov(src: Path, dst: Path, src_root: str) -> dict:
    data = json.loads(src.read_text("utf-8"))
    data.get("meta", {}).pop("timestamp", None)
    prefix = src_root.rstrip("/") + "/"
    data["files"] = {(k[len(prefix):] if k.startswith(prefix) else k): v for k, v in data["files"].items()}
    dump(data, dst)
    t = data["totals"]
    keys = ("covered_lines", "num_statements", "num_branches", "covered_branches", "missing_lines")
    out = {k: int(t[k]) for k in keys if k in t}
    out["percent_covered_display"] = str(t["percent_covered_display"])
    return out


def main():
    out_dir, src_root, deps_root, out_root = (Path(sys.argv[1]),) + tuple(sys.argv[2:5])
    roots = sorted(
        [(src_root, "<SRC>"), (deps_root, "<DEPS>"), (out_root, "<OUT>")], key=lambda r: -len(r[0])
    )
    raw, norm = out_dir / "raw", out_dir / "norm"
    norm.mkdir(exist_ok=True)
    summary = {"junit": norm_junit(raw / "junit.xml", norm / "junit.xml", roots)}
    summary["coverage"] = norm_cov(raw / "coverage.json", norm / "coverage.json", src_root)
    dump(summary, norm / "summary.json")
    digests = {
        "raw/junit.xml": sha256(raw / "junit.xml"),
        "raw/coverage.json": sha256(raw / "coverage.json"),
        "norm/junit.xml": sha256(norm / "junit.xml"),
        "norm/coverage.json": sha256(norm / "coverage.json"),
        "norm/summary.json": sha256(norm / "summary.json"),
    }
    (out_dir / "digests.json").write_text(json.dumps(digests, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"summary": summary, "digests": digests}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
