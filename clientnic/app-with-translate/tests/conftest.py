"""pytest configuration: add app-with-translate to sys.path so tests can import src.*"""

import sys
import os

# Allow `from src.utils.flow_table import ...` etc.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
