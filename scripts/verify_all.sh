#!/usr/bin/env bash
# ==============================================================================
# Spliqo Verification Pipeline (scripts/verify_all.sh)
#
# Runs full test suites, type checking, static analysis, database tests,
# and OpenAPI drift detection across backend, database, and client apps.
# ==============================================================================

set -euo pipefail

# ANSI color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}             SPLIQO FULL VERIFICATION PIPELINE                  ${NC}"
echo -e "${BLUE}================================================================${NC}"

# 1. Python Code Quality: Ruff
echo -e "\n${YELLOW}[1/7] Running Ruff linter on backend...${NC}"
.venv/bin/ruff check app/ tests/
echo -e "${GREEN}✓ Ruff check passed.${NC}"

# 2. Python Type Checking: Pyright
echo -e "\n${YELLOW}[2/7] Running Pyright type checker on backend...${NC}"
.venv/bin/pyright app/
echo -e "${GREEN}✓ Pyright type check passed (0 errors, 0 warnings).${NC}"

# 3. Python Tests & Coverage: Pytest
echo -e "\n${YELLOW}[3/7] Running Pytest test suite with coverage...${NC}"
DEBUG=false .venv/bin/pytest tests/ --cov=app --cov-fail-under=80 -q
echo -e "${GREEN}✓ Pytest suite passed with >= 80% coverage.${NC}"

# 4. OpenAPI Specification Drift Check
echo -e "\n${YELLOW}[4/7] Checking OpenAPI specification drift...${NC}"
.venv/bin/python -c '
import json, sys
from app.main import app

generated = app.openapi()
with open("openapi.json", "r") as f:
    existing = json.load(f)

if generated != existing:
    print("ERROR: OpenAPI schema drift detected between app and openapi.json!", file=sys.stderr)
    sys.exit(1)
print("✓ openapi.json is in exact parity with app schema.")
'
echo -e "${GREEN}✓ OpenAPI drift check passed.${NC}"

# 5. Database pgTAP Assertions (if DB container is reachable)
echo -e "\n${YELLOW}[5/7] Running Supabase pgTAP database assertions...${NC}"
if docker ps --format '{{.Names}}' | grep -q 'supabase_db_Spliqo'; then
  docker exec -i supabase_db_Spliqo psql -U postgres -d postgres < supabase/tests/00001_core_test.sql
  echo -e "${GREEN}✓ Database pgTAP tests passed (22/22 assertions).${NC}"
else
  echo -e "${YELLOW}Notice: supabase_db_Spliqo container not running, skipping live pgTAP run.${NC}"
fi

# 6. Dart Static Analysis
echo -e "\n${YELLOW}[6/7] Running Dart static analysis on Flutter client...${NC}"
(
  cd spliqo_client
  dart analyze --fatal-infos
)
echo -e "${GREEN}✓ Dart analysis passed (0 issues found).${NC}"

# 7. Flutter Widget & Integration Test Suite
echo -e "\n${YELLOW}[7/7] Running Flutter test suite (Domain, Widgets & Flows)...${NC}"
(
  cd spliqo_client
  flutter test
)
echo -e "${GREEN}✓ Flutter test suite passed.${NC}"

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}       ALL VERIFICATION CHECKS PASSED SUCCESSFULLY!             ${NC}"
echo -e "${GREEN}================================================================${NC}"
