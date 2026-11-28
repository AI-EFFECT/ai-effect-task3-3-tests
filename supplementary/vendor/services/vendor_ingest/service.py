"""Stand-in third-party ingest service for the T3.3 external-exchange tests.

Built on the platform's sequential template: handler.py and common/ are copied
from the frozen AI-EFFECT commit by 20-Prepare-Vendor-Pipeline.ps1.

ImportData reads one DataReference (inline, http(s) or file), records its
SHA-256 and size, profiles it as CSV or JSON and writes a normalised JSON
document to the vendor volume. It never modifies the source.
"""

import base64
import csv
import hashlib
import io
import json
import os
import urllib.request
from pathlib import Path

from handler import DataReference, ExecuteRequest, ExecuteResponse, run

DATA_DIR = Path(os.environ.get("VENDOR_DATA_DIR", "/vendor-data"))
MAX_BYTES = int(os.environ.get("VENDOR_MAX_BYTES", str(200 * 1024 * 1024)))
MAX_SERIES_VALUES = 100_000


def _read_reference(ref: dict) -> bytes:
    protocol = str(ref.get("protocol", ""))
    uri = str(ref.get("uri", ""))
    if protocol == "inline":
        data = base64.b64decode(uri)
    elif protocol in ("http", "https"):
        with urllib.request.urlopen(uri, timeout=60) as response:  # noqa: S310 - test service, URI from orchestrator
            data = response.read(MAX_BYTES + 1)
    elif protocol == "file":
        path = Path(uri)
        if not path.is_file():
            raise FileNotFoundError(f"input file not found: {uri}")
        if path.stat().st_size > MAX_BYTES:
            raise ValueError("input exceeds the vendor size limit")
        data = path.read_bytes()
    else:
        raise ValueError(f"Unsupported input protocol: {protocol}")
    if len(data) > MAX_BYTES:
        raise ValueError("input exceeds the vendor size limit")
    return data


def _as_number(value):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None  # drop NaN


def _profile_records(records: list[dict]) -> tuple[list[str], dict]:
    columns: list[str] = []
    for record in records:
        for key in record:
            if key not in columns:
                columns.append(key)
    series = {}
    for column in columns:
        values = [_as_number(r.get(column)) for r in records]
        numeric = [v for v in values if v is not None]
        if numeric and len(numeric) == len([v for v in (r.get(column) for r in records) if v not in (None, "")]):
            series[column] = numeric[:MAX_SERIES_VALUES]
    return columns, series


def _profile(data: bytes, declared_format: str) -> dict:
    text = data.decode("utf-8-sig")
    stripped = text.lstrip()
    if declared_format == "json" or stripped[:1] in ("[", "{"):
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"malformed JSON input: {exc.msg}") from exc
        if isinstance(parsed, list) and all(isinstance(item, dict) for item in parsed):
            columns, series = _profile_records(parsed)
            return {"kind": "json-records", "records": len(parsed), "columns": columns, "series": series}
        if isinstance(parsed, dict):
            return {"kind": "json-object", "records": 1, "columns": sorted(parsed.keys()), "series": {}}
        return {"kind": "json-other", "records": len(parsed) if isinstance(parsed, list) else 1, "columns": [], "series": {}}
    rows = list(csv.DictReader(io.StringIO(text)))
    if not rows:
        raise ValueError("no records found in CSV input")
    columns, series = _profile_records(rows)
    return {"kind": "csv", "records": len(rows), "columns": columns, "series": series}


def execute_ImportData(request: ExecuteRequest) -> ExecuteResponse:
    if not request.inputs:
        raise ValueError("no input reference supplied")
    reference = request.inputs[0]
    data = _read_reference(reference)
    profile = _profile(data, str(reference.get("format", "")))
    document = {
        "generated_by": "vendor_ingest",
        "workflow_id": request.workflow_id,
        "task_id": request.task_id,
        "marker": str(request.parameters.get("marker", "")),
        "source": {
            "protocol": reference.get("protocol"),
            "uri": reference.get("uri") if reference.get("protocol") != "inline" else "(inline)",
            "format": reference.get("format"),
            "sha256": hashlib.sha256(data).hexdigest().upper(),
            "bytes": len(data),
        },
        "profile": {k: v for k, v in profile.items() if k != "series"},
        "series": profile["series"],
    }
    output_dir = DATA_DIR / request.workflow_id
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{request.task_id}.json"
    output_path.write_text(json.dumps(document), encoding="utf-8")
    return ExecuteResponse(status="complete", output=DataReference(protocol="file", uri=str(output_path), format="json"))


if __name__ == "__main__":
    import sys

    run(sys.modules[__name__])
