#!/usr/bin/env bash
# Mint a laptop's IAM user + key as one aws-creds file. Usage: provision_laptop.sh [--dev] [--force] [--host NAME [--owner "Full Name"] [--user macos-account]]
set -euo pipefail
. "$(dirname "$0")/common.sh"

ENV=prod; FORCE=0; HOST=""; OWNER=""; USER_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dev) ENV=dev ;; --force) FORCE=1 ;;
        --host)  HOST="${2:-}";    [[ -n "$HOST" ]]    || { echo "--host needs a name" >&2; exit 1; }; shift ;;
        --owner) OWNER="${2:-}";   [[ -n "$OWNER" ]]   || { echo "--owner needs a name" >&2; exit 1; }; shift ;;
        --user)  USER_ID="${2:-}"; [[ -n "$USER_ID" ]] || { echo "--user needs an account name" >&2; exit 1; }; shift ;;
        *) echo "usage: $0 [--dev] [--force] [--host NAME [--owner \"Full Name\"] [--user macos-account]]" >&2; exit 1 ;;
    esac; shift
done
[[ -z "$HOST" && ( -n "$OWNER" || -n "$USER_ID" ) ]] && { echo "--owner/--user only apply with --host; local mode reads them from this Mac" >&2; exit 1; }
resolve_env "$ENV"
require_sso

LOCAL_HOST="$(hostname -s 2>/dev/null || echo unknown)"   # hostname, not hardware UUID: Apple Silicon regenerates that on reinstall
MINTED_BY="$(whoami)"
if [[ -n "$HOST" ]]; then
    LAPTOP_ID="$HOST"
    TAGS=("Key=laptop_id,Value=$HOST" "Key=minted_on,Value=$LOCAL_HOST" "Key=minted_by,Value=$MINTED_BY")
    [[ -n "$OWNER" ]]   && TAGS+=("Key=display_name,Value=$OWNER")
    [[ -n "$USER_ID" ]] && TAGS+=("Key=user_id,Value=$USER_ID")
else
    LAPTOP_ID="$LOCAL_HOST"
    TAGS=("Key=laptop_id,Value=$LOCAL_HOST" "Key=user_id,Value=$MINTED_BY" "Key=display_name,Value=$(id -F 2>/dev/null || echo "$MINTED_BY")")
fi

sanitize_tag()  { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._:/=+@\- \n' '-' | tr -s '-' | sed 's/^-//; s/-$//'; }
sanitize_name() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9_.-' '-' | tr -s '-' | sed 's/^-//; s/-$//'; }
host="$(sanitize_name "$LAPTOP_ID")"; [[ -n "$host" ]] || { echo "host name '$LAPTOP_ID' sanitizes to nothing" >&2; exit 1; }
IAM_USER="${USER_PREFIX}-${host}"; IAM_USER="${IAM_USER:0:64}"
for i in "${!TAGS[@]}"; do TAGS[$i]="${TAGS[$i]%%,Value=*},Value=$(sanitize_tag "${TAGS[$i]#*,Value=}")"; done

if [[ -n "$HOST" ]]; then OUT="$HOME/.order-upload/minted/$host/aws-creds"; else OUT="$CREDS_FILE"; fi

# refuse before minting, so a refusal never orphans a key
if [[ -f "$OUT" && $FORCE != 1 ]]; then
    echo "refusing to overwrite $OUT; --force to mint again (revoke the old IAM user by hand)" >&2; exit 1
fi
if aws --profile "$PROFILE" iam get-user --user-name "$IAM_USER" >/dev/null 2>&1; then
    echo "IAM user $IAM_USER already exists; to rotate, run the revoke commands from its provisioning output, then re-run" >&2; exit 1
fi
if ! aws --profile "$PROFILE" iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
    "$(dirname "$0")/publish_policy.sh" $( [[ $ENV == dev ]] && echo --dev )
fi

echo "creating IAM user $IAM_USER"
aws --profile "$PROFILE" iam create-user --user-name "$IAM_USER" \
    --tags "${TAGS[@]}" "Key=managed_by,Value=order-upload-provision-laptop" >/dev/null

cleanup_on_failure() {
    echo "provisioning failed; removing partial IAM state for $IAM_USER" >&2
    aws --profile "$PROFILE" iam list-access-keys --user-name "$IAM_USER" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null \
        | tr '\t' '\n' | while read -r k; do [[ -n "$k" ]] && aws --profile "$PROFILE" iam delete-access-key --user-name "$IAM_USER" --access-key-id "$k" 2>/dev/null || true; done
    aws --profile "$PROFILE" iam detach-user-policy --user-name "$IAM_USER" --policy-arn "$POLICY_ARN" 2>/dev/null || true
    aws --profile "$PROFILE" iam delete-user --user-name "$IAM_USER" 2>/dev/null || true
}
trap cleanup_on_failure ERR

aws --profile "$PROFILE" iam attach-user-policy --user-name "$IAM_USER" --policy-arn "$POLICY_ARN"
KEY_JSON=$(aws --profile "$PROFILE" iam create-access-key --user-name "$IAM_USER")
KEY_ID=$(printf '%s' "$KEY_JSON" | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessKey"]["AccessKeyId"])')
SECRET=$(printf '%s' "$KEY_JSON" | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["AccessKey"]["SecretAccessKey"])')
trap - ERR

# the key and its bucket are a matched pair, so the file names both
mkdir -p "$(dirname "$OUT")"; umask 077
cat > "$OUT" <<CREDS
# IAM user ${IAM_USER} (account ${EXPECTED_ACCOUNT}), issued $(date -u +%Y-%m-%d) for ${LAPTOP_ID}
AWS_ACCESS_KEY_ID=${KEY_ID}
AWS_SECRET_ACCESS_KEY=${SECRET}
AWS_DEFAULT_REGION=${REGION}
GS_ORDERS_S3_BUCKET=${BUCKET}
GS_ORDERS_S3_PREFIX=${S3_PREFIX}
CREDS
chmod 600 "$OUT"

if [[ -n "$HOST" ]]; then
    next="next: send that file to the owner of $LAPTOP_ID privately (AirDrop, or a Passwords app shared group). They save it next to
  gs_orders_sync_start.command and double-click start. Delete your copy once they confirm."
else
    next="next: gs_orders_sync_start.command"
fi
cat <<EOT

provisioned
  IAM user:    $IAM_USER${OWNER:+  (owner: $OWNER)}
  access key:  $KEY_ID
  bucket:      s3://$BUCKET/$S3_PREFIX
  file:        $OUT

$next

revoke (lost laptop, scientist leaves):
  aws --profile $PROFILE iam delete-access-key --user-name $IAM_USER --access-key-id $KEY_ID
  aws --profile $PROFILE iam detach-user-policy --user-name $IAM_USER --policy-arn $POLICY_ARN
  aws --profile $PROFILE iam delete-user --user-name $IAM_USER
EOT
