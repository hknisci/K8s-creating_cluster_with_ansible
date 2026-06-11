#!/usr/bin/env bash
set -euo pipefail

# Comprehensive validation script for the platform
# Usage: ./scripts/validate.sh [--env dev|staging|prod] [--skip-tf] [--skip-helm] [--skip-policy]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Defaults
ENVIRONMENT="dev"
SKIP_TF=false
SKIP_HELM=false
SKIP_POLICY=false
ERRORS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; ((ERRORS++)); }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env)       ENVIRONMENT="$2"; shift 2 ;;
      --skip-tf)   SKIP_TF=true; shift ;;
      --skip-helm) SKIP_HELM=true; shift ;;
      --skip-policy) SKIP_POLICY=true; shift ;;
      *) log_warn "Unknown argument: $1"; shift ;;
    esac
  done
}

check_prerequisites() {
  log_info "Checking prerequisites..."
  local missing=()
  command -v terraform &>/dev/null || missing+=("terraform")
  command -v helm      &>/dev/null || missing+=("helm")
  command -v kubectl   &>/dev/null || missing+=("kubectl")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_warn "Optional tools missing: ${missing[*]}"
  fi
  log_info "Prerequisites check done."
}

validate_terraform() {
  if $SKIP_TF; then
    log_warn "Skipping Terraform validation."
    return
  fi

  log_info "Validating Terraform (environment: ${ENVIRONMENT})..."
  local tf_dir="${REPO_ROOT}/terraform/environments/${ENVIRONMENT}"

  if [[ ! -d "$tf_dir" ]]; then
    log_error "Terraform environment directory not found: ${tf_dir}"
    return
  fi

  if ! terraform -chdir="$tf_dir" init -backend=false -input=false -no-color &>/dev/null; then
    log_error "Terraform init failed for ${ENVIRONMENT}"
    return
  fi

  if terraform -chdir="$tf_dir" validate -no-color; then
    log_info "Terraform validation passed for ${ENVIRONMENT}"
  else
    log_error "Terraform validation failed for ${ENVIRONMENT}"
  fi

  if command -v terraform &>/dev/null; then
    if terraform -chdir="${REPO_ROOT}/terraform" fmt -check -recursive -no-color; then
      log_info "Terraform formatting OK"
    else
      log_error "Terraform formatting issues found. Run: terraform fmt -recursive terraform/"
    fi
  fi
}

validate_helm() {
  if $SKIP_HELM; then
    log_warn "Skipping Helm validation."
    return
  fi

  log_info "Validating Helm chart..."
  local chart_dir="${REPO_ROOT}/apps/nodejs-express/helm"

  if ! command -v helm &>/dev/null; then
    log_warn "helm not found, skipping Helm validation."
    return
  fi

  if helm lint "${chart_dir}" \
      -f "${chart_dir}/values.yaml" \
      -f "${chart_dir}/values-${ENVIRONMENT}.yaml" \
      --strict; then
    log_info "Helm lint passed for ${ENVIRONMENT}"
  else
    log_error "Helm lint failed for ${ENVIRONMENT}"
  fi
}

validate_policies() {
  if $SKIP_POLICY; then
    log_warn "Skipping policy validation."
    return
  fi

  log_info "Validating Kyverno policies..."
  if ! command -v kyverno &>/dev/null; then
    log_warn "kyverno CLI not found, skipping policy validation."
    return
  fi

  if kyverno test "${REPO_ROOT}/policies/kyverno/" --detailed-results; then
    log_info "Kyverno policy tests passed"
  else
    log_error "Kyverno policy tests failed"
  fi
}

main() {
  parse_args "$@"
  log_info "Running platform validation for environment: ${ENVIRONMENT}"
  check_prerequisites
  validate_terraform
  validate_helm
  validate_policies

  if [[ $ERRORS -gt 0 ]]; then
    log_error "Validation completed with ${ERRORS} error(s)."
    exit 1
  else
    log_info "All validations passed."
  fi
}

main "$@"
