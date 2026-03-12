"""Add server-app/ to sys.path so tests can import server directly."""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
