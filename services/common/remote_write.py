"""Minimal Prometheus remote_write client — no `protobuf` package dependency.

The remote_write wire format (WriteRequest -> TimeSeries -> Label/Sample) is a
small, fixed protobuf schema, so it's hand-encoded here using raw wire-format
bytes instead of pulling in the full `protobuf` runtime. The only real
dependency is Snappy compression (`cramjam`), which the wire protocol requires.
"""
import struct
import time
import urllib.request

import cramjam


def _varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            break
    return bytes(out)


def _tag(field_number: int, wire_type: int) -> bytes:
    return _varint((field_number << 3) | wire_type)


def _len_delim(field_number: int, data: bytes) -> bytes:
    return _tag(field_number, 2) + _varint(len(data)) + data


def _encode_label(name: str, value: str) -> bytes:
    return _len_delim(1, name.encode()) + _len_delim(2, value.encode())


def _encode_sample(value: float, timestamp_ms: int) -> bytes:
    body = _tag(1, 1) + struct.pack("<d", value)
    body += _tag(2, 0) + _varint(timestamp_ms)
    return body


def _encode_timeseries(labels: dict, samples: list) -> bytes:
    body = b""
    for name, value in labels.items():
        body += _len_delim(1, _encode_label(name, value))
    for value, ts_ms in samples:
        body += _len_delim(2, _encode_sample(value, ts_ms))
    return body


def encode_write_request(series: list) -> bytes:
    """series: [{"labels": {...}, "samples": [(value, ts_ms), ...]}, ...]"""
    body = b""
    for s in series:
        body += _len_delim(1, _encode_timeseries(s["labels"], s["samples"]))
    return body


def push_metrics(
    remote_write_url: str,
    username: str,
    api_key: str,
    metric_prefix: str,
    base_labels: dict,
    gauges: dict,
    timeout_s: int = 10,
) -> None:
    """gauges: {metric_name_suffix: value}. One sample per metric, timestamped now."""
    now_ms = int(time.time() * 1000)
    series = []
    for suffix, value in gauges.items():
        if value is None:
            continue
        labels = {"__name__": f"{metric_prefix}_{suffix}", **base_labels}
        series.append({"labels": labels, "samples": [(float(value), now_ms)]})

    if not series:
        return

    payload = encode_write_request(series)
    compressed = bytes(cramjam.snappy.compress(payload))

    req = urllib.request.Request(
        remote_write_url,
        data=compressed,
        method="POST",
        headers={
            "Content-Type": "application/x-protobuf",
            "Content-Encoding": "snappy",
            "X-Prometheus-Remote-Write-Version": "0.1.0",
            "Authorization": "Basic " + _basic_auth(username, api_key),
        },
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        if resp.status >= 300:
            raise RuntimeError(f"remote_write push failed: HTTP {resp.status}")


def _basic_auth(username: str, password: str) -> str:
    import base64
    return base64.b64encode(f"{username}:{password}".encode()).decode()
