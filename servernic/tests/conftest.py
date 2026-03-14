"""pytest configuration: add app-without-translate to sys.path so tests can import src.*"""

import sys
import os

# Allow `from src.pipeline.rx import ...` etc.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app-without-translate'))
