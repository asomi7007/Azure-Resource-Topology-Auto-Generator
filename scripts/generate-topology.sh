#!/bin/bash

# Azure Resource Topology Auto-Generator
# Cloud Shell Script (UX v3 - Interactive)

set -e

# --- Colors ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Clear screen for fresh start
clear

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   Azure Resource Topology Auto-Generator v1.4   ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# 0. Dependencies
PARSER_SCRIPT="parse-relations.py"
if [ ! -f "$PARSER_SCRIPT" ]; then
    echo -e "Downloading helper script..."
    curl -s -O https://raw.githubusercontent.com/asomi7007/Azure-Resource-Topology-Auto-Generator/master/scripts/parse-relations.py
fi

# 1. Environment Check & Identity
echo -e "${GREEN}[1/5] Checking Environment...${NC}"

# Check Identity
ACCOUNT_INFO=$(az account show -o json 2>/dev/null || echo "")
if [ -z "$ACCOUNT_INFO" ]; then
    echo -e "${YELLOW}Please login to Azure.${NC}"
    az login -o table
    # Retry getting account info after login
    ACCOUNT_INFO=$(az account show -o json 2>/dev/null || echo "")
fi

if [ -n "$ACCOUNT_INFO" ]; then
    USER_NAME=$(echo "$ACCOUNT_INFO" | jq -r '.user.name' 2>/dev/null || echo "User")
    TENANT_ID=$(echo "$ACCOUNT_INFO" | jq -r '.tenantId' 2>/dev/null || echo "Unknown")
    SUB_NAME=$(echo "$ACCOUNT_INFO" | jq -r '.name' 2>/dev/null || echo "Unknown")

    echo -e "User: ${BLUE}$USER_NAME${NC}"
    echo -e "Tenant: $TENANT_ID"
    echo -e "Subscription: ${BLUE}$SUB_NAME${NC}"
else
    echo -e "${RED}[Error] Could not retrieve account info.${NC}"
    exit 1
fi
echo ""

# Extension Check
az config set extension.use_dynamic_install=yes_without_prompt &> /dev/null
if ! az extension show --name resource-graph &>/dev/null; then
    echo -e "${YELLOW}Installing 'resource-graph' extension...${NC}"
    az extension add --name resource-graph --allow-preview true &>/dev/null
fi

# 2. Resource Group Selection (Interactive)
echo -e "${GREEN}[2/5] Fetching Resource Groups...${NC}"
RGS=($(az group list --query "[].name" -o tsv | sort))
COUNT=${#RGS[@]}

if [ "$COUNT" -eq 0 ]; then
    echo -e "${RED}No Resource Groups found.${NC}"
    exit 0
fi

# Selection State Array (0=Unselected, 1=Selected)
# Initialize all to 0
declare -a STATES
for ((i=0; i<COUNT; i++)); do STATES[$i]=0; done

# Helper function to print menu
print_menu() {
    clear
    echo -e "${BLUE}=== Resource Group Selection ===${NC}"
    echo -e "Total: $COUNT groups found."
    echo "--------------------------------"
    
    for ((i=0; i<COUNT; i++)); do
        display_idx=$((i+1))
        if [ "${STATES[$i]}" -eq 1 ]; then
            MARK="[*]"
            COLOR=$GREEN
        else
            MARK="[ ]"
            COLOR=$NC
        fi
        printf " %s %2d. ${COLOR}%s${NC}\n" "$MARK" "$display_idx" "${RGS[$i]}"
    done
    
    echo "--------------------------------"
    # Show currently selected list
    echo -ne "Selected: "
    SELECTED_COUNT=0
    for ((i=0; i<COUNT; i++)); do
        if [ "${STATES[$i]}" -eq 1 ]; then
            if [ "$SELECTED_COUNT" -gt 0 ]; then echo -ne ", "; fi
            echo -ne "${GREEN}${RGS[$i]}${NC}"
            ((SELECTED_COUNT++))
        fi
    done
    if [ "$SELECTED_COUNT" -eq 0 ]; then echo -ne "(None)"; fi
    echo ""
    echo "--------------------------------"
    echo -e "Command Guide:"
    echo -e " - ${YELLOW}Enter Number${NC} : Toggle selection"
    echo -e " - ${YELLOW}Comma list${NC}   : Select multiple (e.g., 1,2,3)"
    echo -e " - ${YELLOW}'0' or Enter${NC} : Select ALL (if nothing selected)"
    echo -e " - ${YELLOW}'00'${NC}         : DONE / Finish Selection"
    echo "--------------------------------"
}

# Initial Loop
FIRST_PASS=true

while true; do
    print_menu
    read -p "Your Choice > " CHOICE
    
    # Handle "00" -> Done
    if [[ "$CHOICE" == "00" ]]; then
        break
    fi

    # Handle Empty or '0' -> Select All (only if first pass or user wants to reset/select all?)
    if [[ -z "$CHOICE" || "$CHOICE" == "0" ]]; then
         # Select ALL
         for ((i=0; i<COUNT; i++)); do STATES[$i]=1; done
         continue
    fi

    # Handle Comma Separated (e.g. 1, 2, 3)
    # Replace commas with spaces
    CHOICE=${CHOICE//,/ }
    
    for num in $CHOICE; do
        if [[ "$num" =~ ^[0-9]+$ ]]; then
            idx=$((num-1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "$COUNT" ]; then
                # Toggle
                if [ "${STATES[$idx]}" -eq 1 ]; then
                    STATES[$idx]=0
                else
                    STATES[$idx]=1
                fi
            fi
        fi
    done
done

# Build Final List
SELECTED_RGS=()
for ((i=0; i<COUNT; i++)); do
    if [ "${STATES[$i]}" -eq 1 ]; then
        SELECTED_RGS+=("${RGS[$i]}")
    fi
done

if [ ${#SELECTED_RGS[@]} -eq 0 ]; then
    echo -e "${RED}No groups selected. Exiting.${NC}"
    exit 0
fi

# 3. Data Collection
echo ""
echo -e "${GREEN}[3/5] Scanning ${#SELECTED_RGS[@]} Groups...${NC}"

KQL_LIST=""
for s_rg in "${SELECTED_RGS[@]}"; do KQL_LIST+="'$s_rg',"; done
KQL_LIST=${KQL_LIST%,}

QUERY="Resources | where resourceGroup in ($KQL_LIST) | project id, name, type, location, tags, properties | order by name asc"
RAW_FILE="resources_raw.json"
TOPOLOGY_FILE="topology.json"

az graph query -q "$QUERY" -o json > "$RAW_FILE"
COUNT_RES=$(jq 'length' "$RAW_FILE" 2>/dev/null || echo "0")
echo -e "Found ${BLUE}$COUNT_RES${NC} resources."

if [ "$COUNT_RES" -eq 0 ]; then
    echo -e "${YELLOW}No resources found.${NC}"
    exit 0
fi

# 4. Generate Topology
echo ""
echo -e "${GREEN}[4/5] Generating Topology...${NC}"
RG_STR=$(IFS=,; echo "${SELECTED_RGS[*]}")
python3 "$PARSER_SCRIPT" "$RAW_FILE" "$TOPOLOGY_FILE" --rg "$RG_STR"

echo -e "${BLUE}Done! '$TOPOLOGY_FILE' created.${NC}"

# 5. Instructions
echo ""
echo -e "${GREEN}[5/5] Next Steps${NC}"
echo -e "1. Download: ${YELLOW}download topology.json${NC}"
echo "2. Upload to server."

echo ""
