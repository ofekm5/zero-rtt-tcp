"""Add client-app/ to sys.path so tests can import client directly."""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
