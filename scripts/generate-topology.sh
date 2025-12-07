#!/bin/bash

# Azure Resource Topology Auto-Generator
# Cloud Shell Script

set -e

echo "=========================================="
echo "   Azure Resource Topology Auto-Generator"
echo "=========================================="
echo ""

# 1. Check Prerequisites
if ! command -v az &> /dev/null; then
    echo "[Error] 'az' command could not be found. Please run this in Azure Cloud Shell."
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "[Error] 'python3' command could not be found. Please run this in Azure Cloud Shell."
    exit 1
fi

# 2. Select Subscription (Optional if already set, but good practice)
echo "[1] Checking current subscription..."
CURRENT_SUB=$(az account show --query "name" -o tsv 2>/dev/null || echo "")

if [ -z "$CURRENT_SUB" ]; then
    echo "No subscription set. Please login via 'az login'."
    exit 1
else
    echo "Current Subscription: $CURRENT_SUB"
fi

# 3. Select Resource Group
echo ""
echo "[2] Fetching Resource Groups..."
# Get list of RGs
RGS=$(az group list --query "[].name" -o tsv)

if [ -z "$RGS" ]; then
    echo "No Resource Groups found in this subscription."
    exit 0
fi

# Simple selection menu
echo "Available Resource Groups:"
select RG in $RGS; do
    if [ -n "$RG" ]; then
        echo "Selected: $RG"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

# 4. Data Collection
echo ""
echo "[3] Collecting Resource Data from Azure Resource Graph..."

# Query definition
# We get all resources in the RG, including some essential properties for linking
QUERY="Resources 
| where resourceGroup == '$RG' 
| project id, name, type, location, tags, properties 
| order by name asc"

# Use tmp file
RAW_FILE="resources_raw.json"
TOPOLOGY_FILE="topology.json"

az graph query -q "$QUERY" -o json > "$RAW_FILE"

COUNT=$(jq 'length' "$RAW_FILE" 2>/dev/null || echo "0")
echo "Collected $COUNT resources."

if [ "$COUNT" -eq 0 ]; then
    echo "[Warning] No resources found in $RG. Exiting."
    exit 0
fi

# 5. Process Relationships (Python)
echo ""
echo "[4] Analyzing Relationships..."

# Check if parser script exists, if not try to download it (simulated for now, assumes local presence for dev)
PARSER_SCRIPT="parse-relations.py"

if [ ! -f "$PARSER_SCRIPT" ]; then
    # In a real scenario, we might curl this from GitHub if missing
    echo "[Info] '$PARSER_SCRIPT' not found in current directory."
    echo "For Development: Assuming we will create it next."
    # Temporary placeholder behavior for flow testing if script missing
    echo "{} " > "$TOPOLOGY_FILE"
else
    python3 "$PARSER_SCRIPT" "$RAW_FILE" "$TOPOLOGY_FILE" --rg "$RG"
fi

echo "Topology JSON generated: $TOPOLOGY_FILE"

# 6. Upload or Deliver
echo ""
read -p "[5] Do you want to generate the Diagram? (y/n): " UPLOAD_CHOICE

if [[ "$UPLOAD_CHOICE" == "y" || "$UPLOAD_CHOICE" == "Y" ]]; then
    # TODO: Replace with actual Server URL
    SERVER_URL="http://localhost:8000/api/topology/upload" 
    echo "Uploading to $SERVER_URL ..."
    
    # Check if curl is available
    if command -v curl &> /dev/null; then
        # Use -F for file upload if the server expects multipart, or -d @file for raw json body
        # PRD said POST JSON body
        RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" --data "@$TOPOLOGY_FILE" "$SERVER_URL" || echo "Upload Failed")
        echo "Server Response: $RESPONSE"
    else
        echo "curl not found."
    fi
else
    echo "Skipping upload."
    echo "You can download '$TOPOLOGY_FILE' locally to use later."
fi

echo ""
echo "Done."
