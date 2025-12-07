#!/bin/bash

# Azure Resource Topology Auto-Generator
# Cloud Shell Script v2.1

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   Azure Resource Topology Auto-Generator        ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# Step 0: Force download latest helper script
echo -e "${GREEN}[Setup] Downloading latest helper script...${NC}"
curl -s -O "https://raw.githubusercontent.com/asomi7007/Azure-Resource-Topology-Auto-Generator/master/scripts/parse-relations.py"

if [ ! -f "parse-relations.py" ]; then
    echo -e "${RED}[Error] Failed to download parse-relations.py${NC}"
    exit 1
fi
echo -e "Helper script ready."
echo ""

# Step 1: Check Azure CLI login
echo -e "${GREEN}[Step 1/5] Checking Azure Login...${NC}"
ACCOUNT_JSON=$(az account show -o json 2>/dev/null)

if [ -z "$ACCOUNT_JSON" ]; then
    echo -e "${YELLOW}Not logged in. Running az login...${NC}"
    az login
    ACCOUNT_JSON=$(az account show -o json 2>/dev/null)
fi

USER_NAME=$(echo "$ACCOUNT_JSON" | jq -r '.user.name // "Unknown"')
SUB_NAME=$(echo "$ACCOUNT_JSON" | jq -r '.name // "Unknown"')
echo -e "Logged in as: ${BLUE}$USER_NAME${NC}"
echo -e "Subscription: ${BLUE}$SUB_NAME${NC}"
echo ""

# Step 2: Check/Install resource-graph extension
echo -e "${GREEN}[Step 2/5] Checking Azure Resource Graph extension...${NC}"
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null

if ! az extension show --name resource-graph &>/dev/null; then
    echo -e "${YELLOW}Installing resource-graph extension...${NC}"
    az extension add --name resource-graph --allow-preview true 2>/dev/null
fi
echo -e "Extension ready."
echo ""

# Step 3: Get Resource Groups and Selection Loop
while true; do
    echo -e "${GREEN}[Step 3/5] Fetching Resource Groups...${NC}"

    # Read into array safely
    mapfile -t RG_LIST < <(az group list --query "[].name" -o tsv | sort)
    RG_COUNT=${#RG_LIST[@]}

    if [ "$RG_COUNT" -eq 0 ]; then
        echo -e "${RED}No Resource Groups found in this subscription.${NC}"
        exit 0
    fi

    echo -e "Found ${BLUE}$RG_COUNT${NC} Resource Groups."
    echo ""

    # Display list
    echo "Available Resource Groups:"
    echo "----------------------------"
    for i in "${!RG_LIST[@]}"; do
        num=$((i+1))
        printf "  [%2d] %s\n" "$num" "${RG_LIST[$i]}"
    done
    echo "----------------------------"
    echo ""

    # Selection prompt
    echo -e "${YELLOW}How to select:${NC}"
    echo -e "  - Enter numbers with comma (e.g., '1,3,5' or '1, 3, 5')"
    echo -e "  - Enter 'all' to select all groups"
    echo -e "  - Press Enter without input to select all"
    echo ""

    read -p "Your selection: " USER_INPUT

    # Process selection
    SELECTED_RGS=()

    if [ -z "$USER_INPUT" ] || [ "$USER_INPUT" = "all" ]; then
        # Select all
        SELECTED_RGS=("${RG_LIST[@]}")
        echo -e "${GREEN}Selected ALL ($RG_COUNT groups)${NC}"
    else
        # Replace commas with spaces and parse numbers
        USER_INPUT=${USER_INPUT//,/ }
        for num in $USER_INPUT; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$RG_COUNT" ]; then
                idx=$((num-1))
                SELECTED_RGS+=("${RG_LIST[$idx]}")
            fi
        done
    fi

    if [ ${#SELECTED_RGS[@]} -eq 0 ]; then
        echo -e "${RED}No valid selection. Please try again.${NC}"
        echo ""
        continue
    fi

    echo ""
    echo -e "You selected ${BLUE}${#SELECTED_RGS[@]}${NC} group(s):"
    for rg in "${SELECTED_RGS[@]}"; do
        echo -e "  - $rg"
    done
    echo ""

    read -p "Continue with these groups? [Y/n]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Going back to selection...${NC}"
        echo ""
        continue
    fi

    # User confirmed, break out of loop
    break
done

# Step 4: Query Resources
echo ""
echo -e "${GREEN}[Step 4/5] Querying Azure Resources...${NC}"

# Build KQL filter
KQL_RGS=""
for rg in "${SELECTED_RGS[@]}"; do
    KQL_RGS+="'$rg',"
done
KQL_RGS=${KQL_RGS%,}  # Remove trailing comma

QUERY="Resources | where resourceGroup in ($KQL_RGS) | project id, name, type, location, tags, properties"

# Determine output directory - prefer clouddrive if available
if [ -d "$HOME/clouddrive" ]; then
    OUTPUT_DIR="$HOME/clouddrive"
    echo -e "${GREEN}Saving files to Cloud Drive (File Share accessible)${NC}"
else
    OUTPUT_DIR="$HOME"
    echo -e "${YELLOW}clouddrive not found, saving to home directory${NC}"
fi

RAW_FILE="$OUTPUT_DIR/resources_raw.json"
TOPOLOGY_FILE="$OUTPUT_DIR/topology.json"

echo -e "Running query..."
az graph query -q "$QUERY" --first 1000 -o json > "$RAW_FILE" 2>/dev/null

if [ ! -f "$RAW_FILE" ]; then
    echo -e "${RED}Failed to query resources.${NC}"
    exit 1
fi

# Count resources (handle az graph output format which wraps in { data: [...] })
RAW_COUNT=$(jq '.data | length' "$RAW_FILE" 2>/dev/null || jq 'length' "$RAW_FILE" 2>/dev/null || echo "0")
echo -e "Found ${BLUE}$RAW_COUNT${NC} resources."

if [ "$RAW_COUNT" = "0" ]; then
    echo -e "${YELLOW}No resources found in selected groups.${NC}"
    exit 0
fi

# Step 5: Generate Topology
echo ""
echo -e "${GREEN}[Step 5/5] Generating Topology JSON...${NC}"

RG_STRING=$(IFS=','; echo "${SELECTED_RGS[*]}")
python3 parse-relations.py "$RAW_FILE" "$TOPOLOGY_FILE" --rg "$RG_STRING"

if [ -f "$TOPOLOGY_FILE" ]; then
    echo ""
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}   SUCCESS!                                      ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
    echo -e "Topology file created: ${GREEN}$TOPOLOGY_FILE${NC}"
    echo ""
    
    if [ -d "$HOME/clouddrive" ]; then
        echo -e "${GREEN}File is saved in your Cloud Drive!${NC}"
        echo -e "You can download it from the Azure Portal:"
        echo -e "  1. Click 'Manage files' icon in Cloud Shell toolbar"
        echo -e "  2. Select 'Open file share'"
        echo -e "  3. Navigate to 'cloudconsole' folder"
        echo -e "  4. Download 'topology.json'"
    else
        echo -e "To download this file to your computer, run:"
        echo -e "  ${YELLOW}download $TOPOLOGY_FILE${NC}"
    fi
    echo ""
    echo -e "Then upload it to the server to generate your diagram."
else
    echo -e "${RED}Failed to generate topology file.${NC}"
    exit 1
fi
