#!/bin/bash
set -e

# Default federated token file path if not provided
AZURE_FEDERATED_TOKEN_FILE=${AZURE_FEDERATED_TOKEN_FILE:-/var/run/secrets/azure/tokens/azure-identity-token}

if [ -z "${AZP_URL}" ]; then
  echo 1>&2 "error: missing AZP_URL environment variable"
  exit 1
fi

# -------------------------------------------------------
# 1. Generate access token to access Azure DevOps
# -------------------------------------------------------
echo "🔐 Logging in using federated identity..."
az login \
  --federated-token "$(cat $AZURE_FEDERATED_TOKEN_FILE)" \
  --service-principal -u $AZURE_CLIENT_ID -t $AZURE_TENANT_ID \
  --allow-no-subscriptions

AZP_TOKEN=$(az account get-access-token \
  --resource 499b84ac-1321-427f-aa17-267ca6975798 \
  --query "accessToken" --output tsv)

if [ -z "${AZP_TOKEN}" ]; then
  echo 1>&2 "error: failed to get Azure DevOps access token"
  exit 1
fi

# -------------------------------------------------------
# 2. Store token in file for config.sh
# -------------------------------------------------------
AZP_TOKEN_FILE="/azp/.token"
echo -n "${AZP_TOKEN}" > "${AZP_TOKEN_FILE}"
unset AZP_TOKEN

# -------------------------------------------------------
# 3. Prepare agent work directory
# -------------------------------------------------------
if [ -n "${AZP_WORK}" ]; then
  mkdir -p "${AZP_WORK}"
fi

# -------------------------------------------------------
# 4. Cleanup handler
# -------------------------------------------------------
cleanup() {
  trap "" EXIT

  if [ -e ./config.sh ]; then
    print_header "🧹 Cleanup. Removing Azure Pipelines agent..."

    # Wait for running jobs to complete before removing
    while true; do
      ./config.sh remove --unattended --auth "PAT" --token $(cat "${AZP_TOKEN_FILE}") && break
      echo "Retrying agent removal in 30 seconds..."
      sleep 30
    done
  fi
}

# -------------------------------------------------------
# 5. Utility print function
# -------------------------------------------------------
print_header() {
  lightcyan="\033[1;36m"
  nocolor="\033[0m"
  echo -e "\n${lightcyan}$1${nocolor}\n"
}

# -------------------------------------------------------
# 6. Ignore token env variables
# -------------------------------------------------------
export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

# -------------------------------------------------------
# 7. Get latest Azure Pipelines agent
# -------------------------------------------------------
print_header "🔍 Determining matching Azure Pipelines agent..."

AZP_AGENT_PACKAGES=$(curl -LsS \
  -u user:$(cat "${AZP_TOKEN_FILE}") \
  -H "Accept:application/json;" \
  "${AZP_URL}/_apis/distributedtask/packages/agent?platform=${TARGETARCH}&top=1")

AZP_AGENT_PACKAGE_LATEST_URL=$(echo "${AZP_AGENT_PACKAGES}" | jq -r ".value[0].downloadUrl")

if [ -z "${AZP_AGENT_PACKAGE_LATEST_URL}" ] || [ "${AZP_AGENT_PACKAGE_LATEST_URL}" == "null" ]; then
  echo 1>&2 "❌ Error: could not determine a matching Azure Pipelines agent"
  exit 1
fi

# -------------------------------------------------------
# 8. Download & extract agent
# -------------------------------------------------------
print_header "📦 Downloading and extracting Azure Pipelines agent..."
curl -LsS "${AZP_AGENT_PACKAGE_LATEST_URL}" | tar -xz & wait $!

source ./env.sh

trap "cleanup; exit 0" EXIT
trap "cleanup; exit 130" INT
trap "cleanup; exit 143" TERM

# -------------------------------------------------------
# 9. Configure the agent
# -------------------------------------------------------
print_header "⚙️ Configuring Azure Pipelines agent..."

./config.sh --unattended \
  --agent "${AZP_AGENT_NAME:-$(hostname)}" \
  --url "${AZP_URL}" \
  --auth "PAT" \
  --token $(cat "${AZP_TOKEN_FILE}") \
  --pool "${AZP_POOL:-Default}" \
  --work "${AZP_WORK:-_work}" \
  --replace \
  --acceptTeeEula & wait $!

# -------------------------------------------------------
# 10. Run the agent
# -------------------------------------------------------
print_header "🚀 Starting Azure Pipelines agent..."
chmod +x ./run.sh
./run.sh "$@" & wait $!
