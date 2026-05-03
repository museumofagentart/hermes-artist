#!/usr/bin/env bash
# Usage: review.sh [--last <n>] [--favorites] [--id <id>] [--json]
source "$(dirname "$0")/helpers.sh"
envelope_success "[]" "{\"source\":\"artist\",\"total\":0,\"model_family\":\"unknown\",\"review_size\":768}"
