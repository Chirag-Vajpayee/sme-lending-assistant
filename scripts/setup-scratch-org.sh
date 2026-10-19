#!/usr/bin/env bash
# Creates a scratch org, deploys fflib and the app, assigns the permission set,
# loads demo data and opens the org. Requires a Dev Hub already authorised with:
#   sf org login web --set-default-dev-hub --alias devhub
set -euo pipefail

ALIAS="${1:-sme-lending}"

sf org create scratch --definition-file config/project-scratch-def.json --alias "$ALIAS" --set-default --duration-days 7 --wait 20
sf project deploy start --target-org "$ALIAS" --wait 30
sf org assign permset --name Lending_Officer --target-org "$ALIAS"
sf apex run --file scripts/apex/seed-demo-data.apex --target-org "$ALIAS"
sf apex run test --target-org "$ALIAS" --test-level RunLocalTests --code-coverage --result-format human --wait 30
sf org open --target-org "$ALIAS" --path lightning/o/Loan_Application__c/list
