#!/usr/bin/env python3
"""Run every brusher in sequence so the output directory is regenerated
end-to-end. Each per-source script can also be run on its own."""

from __future__ import annotations

import brush_benzos_cited
import brush_medtap
import brush_nps
import brush_pyrls


def main() -> None:
    brush_benzos_cited.brush()
    brush_pyrls.brush()
    brush_medtap.brush()
    brush_nps.brush()


if __name__ == "__main__":
    main()
