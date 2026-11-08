
#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="devops-case"
EXPECTED_CONTEXT="k3d-devops-case"
REGISTRY="ghcr.io/iremsilay"
TIMEOUT="180s"

IMAGE_TAG="${1:-}"

if [[ ! "$IMAGE_TAG" =~ ^sha-[0-9a-f]{40}$ ]]; then
  echo "Usage: ./scripts/deploy-local.sh sha-<40-character-git-sha>"
  exit 1
fi

CURRENT_CONTEXT="$(kubectl config current-context)"

if [[ "$CURRENT_CONTEXT" != "$EXPECTED_CONTEXT" ]]; then
  echo "ERROR: Unexpected Kubernetes context: $CURRENT_CONTEXT"
  echo "Expected: $EXPECTED_CONTEXT"
  exit 1
fi

KUBECTL=(kubectl -n "$NAMESPACE")

BACKEND_IMAGE="$REGISTRY/devops-case-backend:$IMAGE_TAG"
FRONTEND_IMAGE="$REGISTRY/devops-case-frontend:$IMAGE_TAG"
ETL_IMAGE="$REGISTRY/devops-case-etl:$IMAGE_TAG"

echo "Target cluster: $CURRENT_CONTEXT"
echo "Namespace: $NAMESPACE"
echo "Image tag: $IMAGE_TAG"

# Verify resources exist.
"${KUBECTL[@]}" get deployment/backend >/dev/null
"${KUBECTL[@]}" get deployment/frontend >/dev/null
"${KUBECTL[@]}" get cronjob/github-etl >/dev/null

# Store current images for rollback.
OLD_BACKEND="$("${KUBECTL[@]}" get deployment/backend \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="backend")].image}')"

OLD_FRONTEND="$("${KUBECTL[@]}" get deployment/frontend \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="frontend")].image}')"

OLD_ETL="$("${KUBECTL[@]}" get cronjob/github-etl \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[?(@.name=="etl")].image}')"

rollback() {
  local exit_code=$?

  trap - ERR
  set +e

  echo "Deployment failed. Starting rollback..."

  local failed=0

  "${KUBECTL[@]}" set image deployment/backend \
    "backend=$OLD_BACKEND" || failed=1

  "${KUBECTL[@]}" set image deployment/frontend \
    "frontend=$OLD_FRONTEND" || failed=1

  "${KUBECTL[@]}" set image cronjob/github-etl \
    "etl=$OLD_ETL" || failed=1

  "${KUBECTL[@]}" rollout status deployment/backend \
    --timeout="$TIMEOUT" || failed=1

  "${KUBECTL[@]}" rollout status deployment/frontend \
    --timeout="$TIMEOUT" || failed=1

  if [[ "$failed" -eq 0 ]]; then
    echo "Rollback completed."
  else
    echo "WARNING: Rollback requires manual inspection."
  fi

  exit "$exit_code"
}

trap rollback ERR

echo "Deploying backend..."
"${KUBECTL[@]}" set image deployment/backend \
  "backend=$BACKEND_IMAGE"

"${KUBECTL[@]}" rollout status deployment/backend \
  --timeout="$TIMEOUT"

echo "Deploying frontend..."
"${KUBECTL[@]}" set image deployment/frontend \
  "frontend=$FRONTEND_IMAGE"

"${KUBECTL[@]}" rollout status deployment/frontend \
  --timeout="$TIMEOUT"

echo "Updating ETL CronJob..."
"${KUBECTL[@]}" set image cronjob/github-etl \
  "etl=$ETL_IMAGE"

# Verify image references.
NEW_BACKEND="$("${KUBECTL[@]}" get deployment/backend \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="backend")].image}')"

NEW_FRONTEND="$("${KUBECTL[@]}" get deployment/frontend \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="frontend")].image}')"

NEW_ETL="$("${KUBECTL[@]}" get cronjob/github-etl \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[?(@.name=="etl")].image}')"

[[ "$NEW_BACKEND" == "$BACKEND_IMAGE" ]]
[[ "$NEW_FRONTEND" == "$FRONTEND_IMAGE" ]]
[[ "$NEW_ETL" == "$ETL_IMAGE" ]]

trap - ERR

echo "Deployment completed successfully."
echo "Backend: $NEW_BACKEND"
echo "Frontend: $NEW_FRONTEND"
echo "ETL: $NEW_ETL"
