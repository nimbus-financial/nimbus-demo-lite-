#!/usr/bin/env bash
# nimbus-demo-lite turnkey deployer for Git Bash / WSL / Linux / macOS.
# Needs only Terraform and the AWS CLI.
#
#   ./deploy.sh --offline preflight render-vars validate
#   ./deploy.sh preflight
#   ./deploy.sh deploy            (alias: all)
#   ./deploy.sh outputs
#   ./deploy.sh destroy
#
# Flags: --offline (no AWS calls), --yes (no prompts), --env-file <path>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE=false
YES=false
ENV_FILE=""
COMMANDS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --offline|-offline|-Offline) OFFLINE=true ;;
    --yes|-yes|-Yes|-y) YES=true ;;
    --env-file|-EnvFile) shift; ENV_FILE="${1:-}" ;;
    -h|--help) COMMANDS+=("help") ;;
    *) COMMANDS+=("$(echo "$1" | tr '[:upper:]' '[:lower:]')") ;;
  esac
  shift
done
[ ${#COMMANDS[@]} -eq 0 ] && COMMANDS=("help")

c_step() { printf '\033[36m==> %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[32m  [ok] %s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m  [warn] %s\033[0m\n' "$*"; }
fail()   { printf '\033[31m  [fail] %s\033[0m\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ paths
IS_WSL=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true
IS_MSYS=false
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) IS_MSYS=true ;; esac

REPO_ROOT_RESOLVED="$SCRIPT_DIR"

to_posix() {
  local p="$1"
  [ -z "$p" ] && { echo ""; return; }
  case "$p" in "~"|"~/"*) p="$HOME${p:1}" ;; esac
  p="${p//\\//}"
  if [[ "$p" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    local d; d="$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
    if $IS_WSL; then p="/mnt/$d${BASH_REMATCH[2]}"; else p="/$d${BASH_REMATCH[2]}"; fi
  elif $IS_MSYS && [[ "$p" =~ ^/mnt/([a-zA-Z])(/.*)?$ ]]; then
    p="/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
  elif $IS_WSL && [[ "$p" =~ ^/([a-zA-Z])(/.*)?$ ]] && [ ! -d "/${BASH_REMATCH[1]}" ]; then
    p="/mnt/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
  fi
  case "$p" in /*) ;; *) p="$REPO_ROOT_RESOLVED/$p" ;; esac
  # collapse duplicate slashes and trailing slash
  p="$(echo "$p" | sed -e 's#//*#/#g' -e 's#\(.\)/$#\1#')"
  echo "$p"
}

# Terraform on Windows (Git Bash) wants C:/... paths in tfvars.
to_tf_path() {
  local p="$1"
  if $IS_MSYS && command -v cygpath >/dev/null 2>&1; then cygpath -m "$p"; else echo "$p"; fi
}

# ------------------------------------------------------------------ env file
declare -A CFG=()

expand_value() {
  local v="$1" out="" name val
  while [[ "$v" =~ ^([^\$]*)\$\{([A-Za-z_][A-Za-z0-9_]*)\}(.*)$ ]]; do
    out+="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"; v="${BASH_REMATCH[3]}"
    if [ -n "${CFG[$name]+x}" ]; then val="${CFG[$name]}"; else val="${!name:-}"; fi
    out+="$val"
  done
  printf '%s' "$out$v"
}

read_env_file() {
  local line key rest val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" =~ ^(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"
    if [[ "$rest" =~ ^\'([^\']*)\' ]] || [[ "$rest" =~ ^\'(.*)$ ]]; then val="${BASH_REMATCH[1]}"
    elif [[ "$rest" =~ ^\"([^\"]*)\" ]] || [[ "$rest" =~ ^\"(.*)$ ]]; then val="${BASH_REMATCH[1]}"
    else val="$(echo "$rest" | sed -e 's/[[:space:]]\{1,\}#.*$//' -e 's/[[:space:]]*$//')"
    fi
    val="$(expand_value "$val")"
    if [ "$key" = "REPO_ROOT" ]; then
      [ -z "$val" ] && val="$SCRIPT_DIR"
      val="$(to_posix "$val")"
      if [ ! -d "$val" ]; then
        c_warn "REPO_ROOT '$val' not found; using script folder '$SCRIPT_DIR'"
        val="$SCRIPT_DIR"
      fi
      REPO_ROOT_RESOLVED="$val"
    fi
    CFG[$key]="$val"
  done < "$1"
}

if [ -z "$ENV_FILE" ]; then
  ENV_FILE="$SCRIPT_DIR/deploy.env"
  if [ ! -f "$ENV_FILE" ]; then
    ENV_FILE="$SCRIPT_DIR/deploy.env.example"
    c_warn "deploy.env not found - using deploy.env.example (copy it to deploy.env and edit the <-- CHANGE lines)"
  fi
fi
ENV_FILE="$(to_posix "$ENV_FILE")"
[ -f "$ENV_FILE" ] || fail "Env file not found: $ENV_FILE"
read_env_file "$ENV_FILE"

cfg() { local v="${CFG[$1]:-}"; if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "${2:-}"; fi; }
cfg_bool() {
  local v; v="$(cfg "$1" "$2" | tr '[:upper:]' '[:lower:]')"
  case "$v" in true|1|yes|y|on) echo true ;; *) echo false ;; esac
}

REPO_ROOT="$REPO_ROOT_RESOLVED"
INFRA_DIR="$(to_posix "$(cfg INFRA_DIR "$REPO_ROOT/infra")")"
APPS_DIR="$(to_posix "$(cfg APPS_DIR "$REPO_ROOT/apps")")"
STATE_DIR="$(to_posix "$(cfg STATE_DIR "$REPO_ROOT/.state")")"
ARTIFACTS_DIR="$(to_posix "$(cfg ARTIFACTS_DIR "$STATE_DIR/artifacts")")"
BACKEND_CFG="$(cfg TF_BACKEND_CONFIG "")"
[ -n "$BACKEND_CFG" ] && BACKEND_CFG="$(to_posix "$BACKEND_CFG")"
TFVARS_FILE="$STATE_DIR/terraform.tfvars.json"
PLAN_FILE="$STATE_DIR/tfplan"
STATE_FILE="$STATE_DIR/terraform.tfstate"
AWS_PROFILE_CFG="$(cfg AWS_PROFILE "")"
AWS_REGION_CFG="$(cfg AWS_REGION us-east-1)"
ACCOUNT_ID="$(cfg AWS_ACCOUNT_ID "")"
PREFIX="$(cfg PROJECT_PREFIX nimbus-demo-lite)"
TF_BIN="$(cfg TERRAFORM_BIN terraform)"
AWS_BIN="$(cfg AWS_BIN aws)"
[ "$TF_BIN" != terraform ] && TF_BIN="$(to_posix "$TF_BIN")"
[ "$AWS_BIN" != aws ] && AWS_BIN="$(to_posix "$AWS_BIN")"
AUTO_APPROVE=$YES
[ "$(cfg_bool AUTO_APPROVE false)" = true ] && AUTO_APPROVE=true

export TF_DATA_DIR="$STATE_DIR/.terraform"
export TF_IN_AUTOMATION=1
export AWS_REGION="$AWS_REGION_CFG" AWS_DEFAULT_REGION="$AWS_REGION_CFG"
[ -n "$AWS_PROFILE_CFG" ] && export AWS_PROFILE="$AWS_PROFILE_CFG"

tf() { (cd "$INFRA_DIR" && "$TF_BIN" "$@") || fail "terraform $* failed"; }

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# ------------------------------------------------------------------ commands
cmd_preflight() {
  c_step "preflight ($($OFFLINE && echo offline || echo live))"
  c_ok "env file  : $ENV_FILE"
  c_ok "REPO_ROOT : $REPO_ROOT"
  [ -d "$INFRA_DIR" ] || fail "INFRA_DIR not found: $INFRA_DIR"; c_ok "INFRA_DIR : $INFRA_DIR"
  [ -d "$APPS_DIR" ] || fail "APPS_DIR not found: $APPS_DIR"; c_ok "APPS_DIR  : $APPS_DIR"
  c_ok "STATE_DIR : $STATE_DIR"
  command -v "$TF_BIN" >/dev/null 2>&1 || fail "terraform not found (https://developer.hashicorp.com/terraform/install)"
  local tfv; tfv="$("$TF_BIN" version -json | sed -n 's/.*"terraform_version": *"\([^"]*\)".*/\1/p' | head -n1)"
  [ "$(printf '%s\n%s\n' 1.6.0 "$tfv" | sort -V | head -n1)" = 1.6.0 ] || fail "Terraform >= 1.6.0 required (found $tfv)"
  c_ok "terraform $tfv"
  [ -f "$APPS_DIR/webhooks/webhook_receiver.py" ] || fail "apps/webhooks/webhook_receiver.py missing under APPS_DIR"
  local cidr; cidr="$(cfg ALLOWED_CIDR 0.0.0.0/0)"
  [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || fail "ALLOWED_CIDR '$cidr' is not an IPv4 CIDR"
  [ "$cidr" = "0.0.0.0/0" ] && c_warn "ALLOWED_CIDR is 0.0.0.0/0 - weak demo endpoints are open to the internet (synthetic data only)"
  [[ "$PREFIX" =~ ^[a-z][a-z0-9-]{2,24}$ ]] || fail "PROJECT_PREFIX must be 3-25 chars of lowercase letters, digits, hyphens"

  if $OFFLINE; then c_ok "offline mode: skipping AWS account checks"; return; fi

  [[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "AWS_ACCOUNT_ID must be a 12-digit account id (got '$ACCOUNT_ID')"
  [ "$ACCOUNT_ID" != 123456789012 ] || fail "AWS_ACCOUNT_ID is still the sample value 123456789012 - set your real account id in deploy.env"
  local email; email="$(cfg OWNER_EMAIL "")"
  if [ "$(cfg_bool ENABLE_BUDGET true)" = true ]; then
    [ -n "$email" ] && [[ "$email" != *@example.com ]] || fail "OWNER_EMAIL is empty or still the example.com sample"
  fi
  [[ "$(cfg BUCKET_SUFFIX "")" != *123456789012* ]] || fail "BUCKET_SUFFIX still contains the sample account id"
  command -v "$AWS_BIN" >/dev/null 2>&1 || fail "AWS CLI v2 not found"
  c_ok "aws cli: $("$AWS_BIN" --version 2>&1)"
  local actual
  actual="$("$AWS_BIN" sts get-caller-identity --query Account --output text 2>&1)" \
    || fail "aws sts get-caller-identity failed (profile '$AWS_PROFILE_CFG'). Run: aws sso login --profile $AWS_PROFILE_CFG
$actual"
  actual="$(echo "$actual" | tr -d '[:space:]')"
  [ "$actual" = "$ACCOUNT_ID" ] || fail "Credentials are for account $actual but AWS_ACCOUNT_ID is $ACCOUNT_ID - refusing to continue"
  c_ok "AWS account $actual matches AWS_ACCOUNT_ID (region $AWS_REGION_CFG)"
}

cmd_render_vars() {
  c_step "render-vars -> $TFVARS_FILE"
  mkdir -p "$STATE_DIR" "$ARTIFACTS_DIR"
  local acct="$ACCOUNT_ID"; $OFFLINE && acct=""
  local budget; budget="$(cfg MONTHLY_BUDGET_USD 50)"
  [[ "$budget" =~ ^[0-9]+(\.[0-9]+)?$ ]] || budget=50
  cat > "$TFVARS_FILE" <<JSON
{
  "project_prefix": $(json_str "$PREFIX"),
  "aws_region": $(json_str "$AWS_REGION_CFG"),
  "aws_account_id": $(json_str "$acct"),
  "owner_email": $(json_str "$(cfg OWNER_EMAIL ops@example.com)"),
  "bucket_suffix": $(json_str "$(cfg BUCKET_SUFFIX -demo)"),
  "cognito_domain_prefix": $(json_str "$(cfg COGNITO_DOMAIN_PREFIX "$PREFIX-auth")"),
  "instance_type": $(json_str "$(cfg INSTANCE_TYPE t3.small)"),
  "db_instance_class": $(json_str "$(cfg DB_INSTANCE_CLASS db.t4g.micro)"),
  "enable_budget": $(cfg_bool ENABLE_BUDGET true),
  "monthly_budget_usd": $budget,
  "allowed_cidr": $(json_str "$(cfg ALLOWED_CIDR 0.0.0.0/0)"),
  "enable_legacy_exposure": $(cfg_bool ENABLE_LEGACY_EXPOSURE true),
  "pq_key_spec": $(json_str "$(cfg PQ_KEY_SPEC ML_DSA_65)"),
  "apps_dir": $(json_str "$(to_tf_path "$APPS_DIR")"),
  "artifacts_dir": $(json_str "$(to_tf_path "$ARTIFACTS_DIR")")
}
JSON
  c_ok "wrote 15 variables"
}

tf_init() {
  mkdir -p "$STATE_DIR"
  if [ "$1" = nobackend ]; then tf init -input=false -no-color -backend=false
  elif [ -n "$BACKEND_CFG" ]; then tf init -input=false -no-color -reconfigure "-backend-config=$(to_tf_path "$BACKEND_CFG")"
  else tf init -input=false -no-color -reconfigure "-backend-config=path=$(to_tf_path "$STATE_FILE")"
  fi
}

cmd_validate() {
  c_step "validate (terraform init -backend=false, fmt -check, validate)"
  tf_init nobackend
  tf fmt -check -recursive -diff; c_ok "terraform fmt -check"
  tf validate -no-color; c_ok "terraform validate"
}

cmd_plan() {
  $OFFLINE && fail "plan needs AWS access; drop --offline"
  cmd_render_vars
  c_step "plan"
  tf_init backend
  tf plan -input=false "-var-file=$(to_tf_path "$TFVARS_FILE")" "-out=$(to_tf_path "$PLAN_FILE")"
  c_ok "plan saved to $PLAN_FILE"
}

cmd_outputs() {
  $OFFLINE && fail "outputs reads state; drop --offline"
  c_step "outputs"
  tf_init backend
  tf output
  (cd "$INFRA_DIR" && "$TF_BIN" output -json > "$STATE_DIR/outputs.json") && c_ok "saved $STATE_DIR/outputs.json"
}

cmd_deploy() {
  $OFFLINE && fail "deploy needs AWS access; drop --offline"
  cmd_preflight
  cmd_render_vars
  c_step "deploy (terraform apply)"
  tf_init backend
  local extra=(); $AUTO_APPROVE && extra=(-auto-approve)
  tf apply -input=false "-var-file=$(to_tf_path "$TFVARS_FILE")" ${extra[@]+"${extra[@]}"}
  cmd_outputs
  echo
  echo "Deployed. The EC2 host needs ~5 minutes after apply to install Docker and start containers."
  echo "Shell access: aws ssm start-session --target <ec2_instance_id>"
}

cmd_destroy() {
  $OFFLINE && fail "destroy needs AWS access; drop --offline"
  cmd_preflight
  cmd_render_vars
  if ! $AUTO_APPROVE; then
    local answer
    read -r -p "Type the project prefix '$PREFIX' to DESTROY everything in account $ACCOUNT_ID: " answer
    [ "$answer" = "$PREFIX" ] || fail "destroy cancelled"
  fi
  c_step "destroy (terraform destroy)"
  tf_init backend
  tf destroy -input=false -auto-approve "-var-file=$(to_tf_path "$TFVARS_FILE")"
  c_ok "all resources destroyed (state kept in $STATE_DIR)"
}

show_help() {
  cat <<'HELP'
nimbus-demo-lite deployer (bash)

Usage: ./deploy.sh [--offline] [--yes] [--env-file <path>] <command> [<command> ...]

Commands:
  preflight    check tools, paths and (unless --offline) that AWS creds match AWS_ACCOUNT_ID
  render-vars  write STATE_DIR/terraform.tfvars.json from deploy.env
  validate     terraform init -backend=false + fmt -check + validate (no AWS needed)
  plan         terraform plan (saved to STATE_DIR/tfplan)
  deploy       preflight + render-vars + terraform apply + outputs   (alias: all)
  outputs      print endpoints and save STATE_DIR/outputs.json
  destroy      terraform destroy (asks you to type the project prefix unless --yes)
HELP
}

for c in "${COMMANDS[@]}"; do
  case "$c" in
    preflight) cmd_preflight ;;
    render-vars) cmd_render_vars ;;
    validate) cmd_validate ;;
    plan) cmd_plan ;;
    deploy|all|apply) cmd_deploy ;;
    outputs) cmd_outputs ;;
    destroy) cmd_destroy ;;
    help) show_help ;;
    *) show_help; fail "unknown command '$c'" ;;
  esac
done
c_ok "Done: ${COMMANDS[*]}"
