#!/bin/bash
set -eu
PYTHONDONTWRITEBYTECODE=1 python3 "$(dirname "$0")/test-chatgpt-executor.py"
