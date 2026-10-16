#!/usr/bin/env python3
"""Compatibility entry point: prepare the current CoreMark board packages."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name("prepare_coremark_board.py")), run_name="__main__")
