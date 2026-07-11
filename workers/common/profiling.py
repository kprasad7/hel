"""Shared GPU/timing profiling helpers used by every RunPod worker.

Kept dependency-light (pynvml only) so it can be copied verbatim into each
worker's Docker image without pulling in stage-specific ML libraries.
"""
import threading
import time


class GpuProfiler:
    """Samples GPU utilization/memory/power on a background thread.

    Use as a context manager around the inference call so samples cover
    exactly the inference window, not model load or upload time.
    """

    def __init__(self, device_index: int = 0, interval_s: float = 0.25):
        self.device_index = device_index
        self.interval_s = interval_s
        self._utilization = []
        self._memory_used_mb = []
        self._power_watts = []
        self._stop_event = threading.Event()
        self._thread = None
        self._device_name = "unknown"
        self._pynvml = None

    def __enter__(self):
        try:
            import pynvml
            self._pynvml = pynvml
            pynvml.nvmlInit()
            handle = pynvml.nvmlDeviceGetHandleByIndex(self.device_index)
            name = pynvml.nvmlDeviceGetName(handle)
            self._device_name = name.decode() if isinstance(name, bytes) else name
            self._thread = threading.Thread(target=self._sample_loop, args=(handle,), daemon=True)
            self._thread.start()
        except Exception:
            # Profiling must never break inference (e.g. no GPU visible locally).
            self._pynvml = None
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=2)
        if self._pynvml:
            try:
                self._pynvml.nvmlShutdown()
            except Exception:
                pass

    def _sample_loop(self, handle):
        pynvml = self._pynvml
        while not self._stop_event.is_set():
            try:
                util = pynvml.nvmlDeviceGetUtilizationRates(handle)
                mem = pynvml.nvmlDeviceGetMemoryInfo(handle)
                power = pynvml.nvmlDeviceGetPowerUsage(handle)
                self._utilization.append(util.gpu)
                self._memory_used_mb.append(mem.used // (1024 * 1024))
                self._power_watts.append(round(power / 1000.0, 1))
            except Exception:
                pass
            self._stop_event.wait(self.interval_s)

    def summary(self) -> dict:
        return {
            "device": self._device_name,
            "utilization_pct_samples": self._utilization,
            "memory_used_mb_samples": self._memory_used_mb,
            "power_watts_samples": self._power_watts,
        }


class StageTimer:
    """Named wall-clock timing blocks, collected into a flat ms dict."""

    def __init__(self):
        self.timings_ms: dict[str, float] = {}

    def measure(self, name: str):
        return _TimingBlock(self, name)

    def set(self, name: str, value_ms: float):
        self.timings_ms[name] = round(value_ms, 2)


class _TimingBlock:
    def __init__(self, timer: StageTimer, name: str):
        self._timer = timer
        self._name = name
        self._start = None

    def __enter__(self):
        self._start = time.perf_counter()
        return self

    def __exit__(self, *exc):
        self._timer.set(self._name, (time.perf_counter() - self._start) * 1000)
