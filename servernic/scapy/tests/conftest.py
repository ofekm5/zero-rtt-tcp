"""pytest configuration: add scapy/ to sys.path so tests can import src.*"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
