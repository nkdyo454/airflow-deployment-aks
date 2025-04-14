#!/bin/bash
set -e

if [ -z "${AZP_URL}" ]; then
  echo >&2 "Missing AZP_URL"
  exit 1
fi

echo "Logging in with Managed Identity..."
az login --identity --username b0286c26-da34-4a62-84e5-aa896a841c8c
AZP_TOKEN=$(az account get-access-token --query accessToken --output tsv)
echo "Token acquired via Managed Identity"

AZP_TOKEN_FILE="/azp/.token"
echo -n "${AZP_TOKEN}" > "${AZP_TOKEN_FILE}"

export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

print_header() {
  echo -e "\n\033[1;36m$1\033[0m\n"
}

cleanup() {
  trap "" EXIT
  if [ -e ./config.sh ]; then
    print_header "Cleaning up agent config"
    while true; do
      ./config.sh remove --unattended --auth PAT --token $(cat "${AZP_TOKEN_FILE}") && break
      echo "Retrying removal in 30s..."
      sleep 30
    done
  fi
}

print_header "Fetching latest agent package"
AGENT_URL=$(curl -LsS -u user:$(cat "${AZP_TOKEN_FILE}") \
  -H "Accept:application/json" \
  "${AZP_URL}/_apis/distributedtask/packages/agent?platform=${TARGETARCH}&top=1" | jq -r ".value[0].downloadUrl")

curl -LsS "$AGENT_URL" | tar -xz & wait $!
source ./env.sh

trap "cleanup; exit 0" EXIT
trap "cleanup; exit 130" INT
trap "cleanup; exit 143" TERM

print_header "Configuring agent"

./config.sh --unattended \
  --agent "${AZP_AGENT_NAME:-$(hostname)}" \
  --url "${AZP_URL}" \
  --auth "PAT" \
  --token $(cat "${AZP_TOKEN_FILE}") \
  --pool "${AZP_POOL:-Default}" \
  --work "${AZP_WORK:-_work}" \
  --replace \
  --acceptTeeEula & wait $!

print_header "Running agent"
chmod +x ./run.sh
./run.sh "$@" & wait $!
