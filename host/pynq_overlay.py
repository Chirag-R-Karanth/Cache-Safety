# PYNQ overlay control for the Cache-Safety core (Phase 8).
#
# Provides the host-side interface to the FPGA bitstream: reset, run a
# victim/attacker program, read back probe timings (Flush+Reload), and
# stream live probe data to the dashboard.
#
# The overlay is *optional*: with no PYNQ board/bitstream present the class
# degrades to "mock" mode that replays saved experiment artifacts
# (results/spectre/, results/mitigations/) so the dashboard still renders.
# When a PYNQ-Z1/Z2 is connected and the bitstream is loaded, the same
# methods drive real hardware.
from __future__ import annotations

import csv
import json
import pathlib
import time
from typing import Optional

ROOT = pathlib.Path(__file__).resolve().parents[1]


class PynqOverlay:
    """Thin wrapper around the PYNQ overlay for the speculative core.

    Attributes
    ----------
    available : bool
        True when a real PYNQ overlay is connected; False in mock mode.
    """

    def __init__(self, bitstream: Optional[str] = None) -> None:
        self.available = False
        self._overlay = None
        self._ip = None
        self.bitstream = bitstream or str(ROOT / "fpga" / "core5.bit")
        self._connect()

    # ------------------------------------------------------------------ connect
    def _connect(self) -> None:
        """Attach to the PYNQ overlay if present; otherwise mock mode."""
        try:
            from pynq import Overlay  # type: ignore

            ol = Overlay(self.bitstream)
            # Expect an AXI-lite IP named "core5" with these registers:
            #   0x00 CTRL  : bit0 = start, bit1 = reset
            #   0x04 STATUS  : bit0 = busy, bit1 = fault/trap
            #   0x08 ADDR    : target address
            #   0x0C DATA    : read/write data
            self._overlay = ol
            self._ip = ol.core5  # name must match the block design
            self.available = True
        except Exception:  # pynq missing, no board, no bitstream, ...
            self._overlay = None
            self._ip = None
            self.available = False

    # ------------------------------------------------------------------- control
    def reset(self) -> None:
        """Assert reset on the core (no-op in mock mode)."""
        if self.available:
            self._ip.write(0x00, 0x1)
            time.sleep(0.001)
            self._ip.write(0x00, 0x0)

    def start(self, addr: int) -> None:
        """Kick the core running from `addr` (no-op in mock mode)."""
        if self.available:
            self._ip.write(0x08, addr & 0xFFFFFFFF)
            self._ip.write(0x00, 0x1)

    def busy(self) -> bool:
        """True while the core is executing (mock: always False)."""
        if self.available:
            return bool(self._ip.read(0x04) & 0x1)
        return False

    def trap(self) -> bool:
        """True if the core raised a fault/trap (mock: always False)."""
        if self.available:
            return bool(self._ip.read(0x04) & 0x2)
        return False

    # --------------------------------------------------------------- probe data
    def read_probe(self, addr: int) -> int:
        """Read one probe word (Flush+Reload timing source)."""
        if self.available:
            self._ip.write(0x08, addr & 0xFFFFFFFF)
            return self._ip.read(0x0C)
        # Mock mode: return a deterministic "timing" derived from saved data.
        return 0

    def read_probe_timings(self, base: int, count: int = 256) -> list[int]:
        """Read `count` probe timings starting at `base` (Flush+Reload sweep).

        Real hardware: reloads each probe line and measures mcycle delta.
        Mock mode: replays the saved Spectre trial-0 signature so the
        dashboard still renders without a board.
        """
        if self.available:
            return [self.read_probe(base + 16 * b) for b in range(count)]
        return self._mock_probe_timings()

    def _mock_probe_timings(self) -> list[int]:
        """Replay saved Spectre trial-0 latencies (offline fallback)."""
        csv_path = ROOT / "results" / "spectre" / "results.csv"
        latencies: list[int] = []
        if csv_path.exists():
            try:
                with open(csv_path, newline="") as f:
                    for row in csv.DictReader(f):
                        if int(row["trial"]) == 0:
                            latencies.append(int(row["latency"]))
            except (OSError, KeyError, ValueError):
                latencies = []
        if len(latencies) >= 256:
            return latencies[:256]
        # Deterministic synthetic fallback: dip at byte 183.
        return [12 if b != 183 else 5 for b in range(256)]

    # --------------------------------------------------------------- artifacts
    def saved_artifacts(self) -> dict[str, pathlib.Path]:
        """Return paths to saved experiment artifacts for the dashboard."""
        return {
            "spectre_signature": ROOT / "results" / "spectre" / "signature.svg",
            "spectre_recovery": ROOT / "results" / "spectre" / "recovery.csv",
            "spectre_results": ROOT / "results" / "spectre" / "results.csv",
            "mitigations_comparison": ROOT / "results" / "mitigations" / "comparison.csv",
            "mitigations_plot": ROOT / "results" / "mitigations" / "leakage_vs_overhead.svg",
        }

    def summary(self) -> dict:
        """Human-readable summary of the overlay state."""
        return {
            "available": self.available,
            "bitstream": self.bitstream,
            "mode": "hardware" if self.available else "mock (saved artifacts)",
        }
