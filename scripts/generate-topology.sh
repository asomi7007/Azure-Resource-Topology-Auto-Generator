#!/bin/bash

# Azure Resource Topology Auto-Generator
# Cloud Shell Script (Enhanced UX)

set -e

# --- Helper Colors ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   Azure Resource Topology Auto-Generator v1.2   ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# 0. Auto-download dependency if missing
PARSER_SCRIPT="parse-relations.py"
if [ ! -f "$PARSER_SCRIPT" ]; then
    echo -e "${YELLOW}[Init] Downloading dependency: $PARSER_SCRIPT...${NC}"
    curl -s -O https://raw.githubusercontent.com/asomi7007/Azure-Resource-Topology-Auto-Generator/master/scripts/parse-relations.py
fi

# 1. Prerequisite Checks & Config
echo -e "${GREEN}[Step 1/5] Checking Environment...${NC}"

# Auto-configure extension installation to prevent hanging
# This suppresses prompts for 'resource-graph' extension installation
az config set extension.use_dynamic_install=yes_without_prompt &> /dev/null
az config set extension.dynamic_install_allow_preview=true &> /dev/null

if ! command -v az &> /dev/null; then
    echo -e "${RED}[Error] 'az' command not found. Run this in Azure Cloud Shell.${NC}"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}[Error] 'python3' command not found.${NC}"
    exit 1
fi

# 2. Select Subscription
echo -e "${GREEN}[Step 2/5] Selecting Subscription...${NC}"
CURRENT_SUB=$(az account show --query "name" -o tsv 2>/dev/null || echo "")

if [ -z "$CURRENT_SUB" ]; then
    echo -e "${YELLOW}Please login to Azure.${NC}"
    az login -o table
    CURRENT_SUB=$(az account show --query "name" -o tsv)
fi
echo -e "Current Subscription: ${BLUE}$CURRENT_SUB${NC}"
echo ""

# 3. Select Resource Groups (Multi-Select)
echo -e "${GREEN}[Step 3/5] Fetching Resource Groups...${NC}"
# Get list of RGs as "Name"
RGS=($(az group list --query "[].name" -o tsv | sort))

if [ ${#RGS[@]} -eq 0 ]; then
    echo -e "${RED}[Error] No Resource Groups found.${NC}"
    exit 0
fi

echo "Available Resource Groups:"
i=1
for rg in "${RGS[@]}"; do
    echo "  [$i] $rg"
    ((i++))
done

echo ""
echo -e "${YELLOW}Enter the numbers of the Resource Groups to scan.${NC}"
echo -e "${YELLOW}Examples: '1' or '1 3 5' or 'all'${NC}"
read -p "Selection: " SELECTION

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
    echo -e "${RED}[Error] No valid selection made. Exiting.${NC}"
    exit 1
fi

echo ""
echo -e "You selected ${#SELECTED_RGS[@]} Resource Group(s):"
for s_rg in "${SELECTED_RGS[@]}"; do
    echo -e " - ${BLUE}$s_rg${NC}"
done

echo ""
read -p "Are you sure you want to proceed? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Operation cancelled."
    exit 0
fi

# 4. Data Collection (Batch Query)
echo ""
echo -e "${GREEN}[Step 4/5] Collecting Resource Data...${NC}"

# Build KQL "in" clause: ('rg1', 'rg2')
KQL_LIST=""
for s_rg in "${SELECTED_RGS[@]}"; do
    KQL_LIST+="'$s_rg',"
done
# Remove trailing comma
KQL_LIST=${KQL_LIST%,}

# Query definition
# Querying multiple RGs at once
echo -e "Querying Azure Resource Graph..."
QUERY="Resources 
| where resourceGroup in ($KQL_LIST) 
| project id, name, type, location, tags, properties 
| order by name asc"

RAW_FILE="resources_raw.json"
TOPOLOGY_FILE="topology.json"

# Run query
az graph query -q "$QUERY" -o json > "$RAW_FILE"

COUNT=$(jq 'length' "$RAW_FILE" 2>/dev/null || echo "0")
echo -e "${BLUE}Success! Collected $COUNT resources.${NC}"

if [ "$COUNT" -eq 0 ]; then
    echo -e "${YELLOW}[Warning] No resources found in selected groups.${NC}"
    exit 0
fi

# 5. Process Relationships
echo ""
echo -e "${GREEN}[Step 5/5] Analyzing Relationships & Generating Topology...${NC}"

if [ -f "$PARSER_SCRIPT" ]; then
    # We pass the list of RGs just for metadata, though parser uses the raw file mostly
    # Joining RGs with comma for display/arg
    RG_STR=$(IFS=,; echo "${SELECTED_RGS[*]}")
    
    python3 "$PARSER_SCRIPT" "$RAW_FILE" "$TOPOLOGY_FILE" --rg "$RG_STR"
    echo -e "${BLUE}Topology JSON generated successfully: $TOPOLOGY_FILE${NC}"
else
    echo -e "${RED}[Error] Parser script missing. Cannot generate topology.${NC}"
    exit 1
fi

# 6. Final Instructions
echo ""
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}                 COMPLETED                       ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
echo "Your topology file is ready: 'topology.json'"
echo ""
echo "To download it to your local machine, run:"
echo -e "${GREEN}download topology.json${NC}"
echo ""
echo "Then upload it to the server to verify the changes."
