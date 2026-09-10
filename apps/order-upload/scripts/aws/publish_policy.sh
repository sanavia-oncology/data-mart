#!/usr/bin/env bash
# Create or update the managed policy every laptop user is attached to. Usage: publish_policy.sh [--dev]
set -euo pipefail
. "$(dirname "$0")/common.sh"

ENV=prod
for a in "$@"; do case "$a" in --dev) ENV=dev ;; *) echo "usage: $0 [--dev]" >&2; exit 1 ;; esac; done
resolve_env "$ENV"
require_sso

DOC=$(mktemp); trap 'rm -f "$DOC"' EXIT
policy_json > "$DOC"
/usr/bin/python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$DOC"

if aws --profile "$PROFILE" iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
    n=$(aws --profile "$PROFILE" iam list-policy-versions --policy-arn "$POLICY_ARN" \
        --query 'length(Versions[?IsDefaultVersion==`false`])' --output text)
    if [[ "$n" -ge 4 ]]; then   # AWS caps versions at 5
        oldest=$(aws --profile "$PROFILE" iam list-policy-versions --policy-arn "$POLICY_ARN" \
            --query 'sort_by(Versions[?IsDefaultVersion==`false`],&CreateDate)[0].VersionId' --output text)
        aws --profile "$PROFILE" iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$oldest"
    fi
    v=$(aws --profile "$PROFILE" iam create-policy-version --policy-arn "$POLICY_ARN" \
        --policy-document "file://$DOC" --set-as-default --query PolicyVersion.VersionId --output text)
    echo "$POLICY_NAME: new default version $v"
else
    aws --profile "$PROFILE" iam create-policy --policy-name "$POLICY_NAME" \
        --description "order-upload per-laptop policy: s3 sync add-only (Put+List, no Get/Delete) on ${BUCKET}." \
        --policy-document "file://$DOC" >/dev/null
    echo "created $POLICY_ARN"
fi
