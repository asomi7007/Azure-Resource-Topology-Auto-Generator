#!/bin/bash

# Azure Resource Topology Auto-Generator
# Cloud Shell Script (Enhanced UX v2)

set -e

# --- Colors ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   Azure Resource Topology Auto-Generator v1.3   ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# 0. Dependencies
PARSER_SCRIPT="parse-relations.py"
if [ ! -f "$PARSER_SCRIPT" ]; then
    echo -e "Downloading helper script..."
    curl -s -O https://raw.githubusercontent.com/asomi7007/Azure-Resource-Topology-Auto-Generator/master/scripts/parse-relations.py
fi

# 1. Environment Check
echo -e "${GREEN}[1/5] Checking Environment & Identity...${NC}"

# 1.1 Check Identity
ACCOUNT_INFO=$(az account show -o json 2>/dev/null || echo "")
if [ -z "$ACCOUNT_INFO" ]; then
    echo -e "${YELLOW}You are not logged in.${NC}"
    az login -o table
    ACCOUNT_INFO=$(az account show -o json)
fi

USER_NAME=$(echo "$ACCOUNT_INFO" | jq -r '.user.name')
TENANT_ID=$(echo "$ACCOUNT_INFO" | jq -r '.tenantId')
SUB_NAME=$(echo "$ACCOUNT_INFO" | jq -r '.name')

echo -e "Hello, ${BLUE}$USER_NAME${NC}!"
echo -e "Tenant ID: $TENANT_ID"
echo -e "Subscription: ${BLUE}$SUB_NAME${NC}"
echo ""

# 1.2 Check Extensions
echo -e "Checking required extensions..."
# Configure auto-install to be silent just in case, but we try to be explicit first
az config set extension.use_dynamic_install=yes_without_prompt &> /dev/null

if ! az extension show --name resource-graph &>/dev/null; then
    echo -e "${YELLOW}Extension 'resource-graph' is missing. Installing now...${NC}"
    az extension add --name resource-graph --allow-preview true &>/dev/null
    echo -e "Extension installed."
else
    echo -e "Extension 'resource-graph' is ready."
fi
echo ""

# 2. Select Resource Groups
echo -e "${GREEN}[2/5] Fetching Resource Groups in '$SUB_NAME'...${NC}"
RGS=($(az group list --query "[].name" -o tsv | sort))

if [ ${#RGS[@]} -eq 0 ]; then
    echo -e "${RED}No Resource Groups found. Exiting.${NC}"
    exit 0
fi

# Limit display if too many?
i=1
for rg in "${RGS[@]}"; do
    printf "  [%2d] %s\n" "$i" "$rg"
    ((i++))
done

echo ""
echo -e "${YELLOW}Select Groups (e.g. '1', '1 3', 'all')${NC}"
read -p "Selection [Default: all]: " SELECTION
SELECTION=${SELECTION:-all} # Default to all

SELECTED_RGS=()
if [[ "$SELECTION" == "all" ]]; then
    SELECTED_RGS=("${RGS[@]}")
else
    for num in $SELECTION; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#RGS[@]}" ]; then
            idx=$((num-1))
            SELECTED_RGS+=("${RGS[$idx]}")
        fi
    done
fi

if [ ${#SELECTED_RGS[@]} -eq 0 ]; then
    echo -e "${RED}Invalid selection. Exiting.${NC}"
    exit 1
fi

echo ""
echo -e "Target: ${BLUE}${#SELECTED_RGS[@]} Resource Group(s)${NC}"
if [ ${#SELECTED_RGS[@]} -le 5 ]; then
    for s_rg in "${SELECTED_RGS[@]}"; do echo " - $s_rg"; done
fi

read -p "Proceed with scan? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y} # Default Yes

if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# 3. Data Collection
echo ""
echo -e "${GREEN}[3/5] Scanning Resources...${NC}"

KQL_LIST=""
for s_rg in "${SELECTED_RGS[@]}"; do KQL_LIST+="'$s_rg',"; done
KQL_LIST=${KQL_LIST%,}

QUERY="Resources | where resourceGroup in ($KQL_LIST) | project id, name, type, location, tags, properties | order by name asc"
RAW_FILE="resources_raw.json"
TOPOLOGY_FILE="topology.json"

az graph query -q "$QUERY" -o json > "$RAW_FILE"
COUNT=$(jq 'length' "$RAW_FILE" 2>/dev/null || echo "0")
echo -e "Found ${BLUE}$COUNT${NC} resources."

if [ "$COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No resources to map. Exiting.${NC}"
    exit 0
fi

# 4. Generate Topology
echo ""
echo -e "${GREEN}[4/5] Generating Topology...${NC}"
# Pass RGs just for info
RG_STR=$(IFS=,; echo "${SELECTED_RGS[*]}")
python3 "$PARSER_SCRIPT" "$RAW_FILE" "$TOPOLOGY_FILE" --rg "$RG_STR"

echo -e "${BLUE}Success! Created '$TOPOLOGY_FILE'.${NC}"


# 5. Download Instructions
echo ""
echo -e "${GREEN}[5/5] Next Steps${NC}"
echo "We are done here. To generate the diagram:"
echo "1. Download the file:"
echo -e "   ${YELLOW}download $TOPOLOGY_FILE${NC}"
echo "2. Upload it to the server."

# Clean exit
echo ""
