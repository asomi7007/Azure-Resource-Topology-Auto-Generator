import json
import sys
import argparse

def main():
    parser = argparse.ArgumentParser(description='Parse Azure Resources to Topology JSON')
    parser.add_argument('input_file', help='Input raw JSON file from az graph')
    parser.add_argument('output_file', help='Output topology JSON file')
    parser.add_argument('--rg', help='Resource Group Name', required=True)
    args = parser.parse_args()

    # Load raw resources with robust handling
    try:
        with open(args.input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        # Handle case where output might be wrapped or single object
        if isinstance(data, list):
            resources = data
        elif isinstance(data, dict):
            # Sometimes single object or dictionary wrapper
            if 'data' in data and isinstance(data['data'], list):
                resources = data['data']
            else:
                resources = [data]
        else:
            print(f"[Error] content is not a list/dict: {type(data)}")
            resources = []

    except Exception as e:
        print(f"[Error] Failed to load JSON: {e}")
        # Create empty topology so flow doesn't break entirely? Or exit?
        # Exit is better to show error.
        sys.exit(1)

    # Validate resource structure
    valid_resources = []
    for r in resources:
        if isinstance(r, dict) and 'id' in r:
            valid_resources.append(r)
        else:
            # Skip invalid entries (could be strings or malformed objects)
            continue
    
    resources = valid_resources
    
    # Init Topology
    topology = {
        "resourceGroup": args.rg,
        "resources": [],
        "relationships": []
    }

    # Helper: Search resource by ID
    # In a large set, a dict map is faster
    resource_map = {r['id'].lower(): r for r in resources}
    print(f"Loaded {len(resources)} valid resources.")
    
    # 1. Process Resources
    for r in resources:
        # Simplify Type for easier icon mapping later
        node = {
            "id": r['id'],
            "name": r['name'],
            "type": r['type'],
            "location": r['location'],
            "tags": r.get('tags', {}),
            "properties": r.get('properties', {}) 
        }
        topology["resources"].append(node)

    # 2. Process Relationships with Categories
    relationships = []

    for r in resources:
        rid = r['id'].lower()
        rtype = r['type'].lower()
        props = r.get('properties', {})

        # --- Rule: VNet -> Subnet (Physical/Contains) ---
        if rtype == 'microsoft.network/virtualnetworks':
            subnets = props.get('subnets', [])
            for sn in subnets:
                sn_id = sn.get('id')
                if sn_id:
                    relationships.append({
                        "from": rid,
                        "to": sn_id.lower(),
                        "type": "Contains",
                        "category": "Physical", # Drawn as container box
                        "style": "none"         # No line, just containment
                    })
                    # Ensure Subnet Node Exists
                    if sn_id.lower() not in resource_map:
                        sub_node = {
                            "id": sn_id,
                            "name": sn.get('name'),
                            "type": "Microsoft.Network/virtualNetworks/subnets",
                            "location": r['location'],
                            "properties": sn.get('properties', {})
                        }
                        # Check if already added
                        if not any(x['id'].lower() == sn_id.lower() for x in topology['resources']):
                            topology['resources'].append(sub_node)

        # --- Rule: Subnet -> NIC (Physical/Membership) ---
        if rtype == 'microsoft.network/networkinterfaces':
            ip_configs = props.get('ipConfigurations', [])
            for ip in ip_configs:
                subnet_ref = ip.get('properties', {}).get('subnet', {})
                sub_id = subnet_ref.get('id')
                if sub_id:
                     relationships.append({
                        "from": sub_id.lower(),
                        "to": rid,
                        "type": "Attached",
                        "category": "Physical",
                        "style": "solid" # Or just placement inside
                    })

        # --- Rule: NIC -> VM (Physical/Attached) ---
        if rtype == 'microsoft.compute/virtualmachines':
            net_profile = props.get('networkProfile', {})
            nics = net_profile.get('networkInterfaces', [])
            for nic_ref in nics:
                nic_id = nic_ref.get('id')
                if nic_id:
                    relationships.append({
                        "from": nic_id.lower(),
                        "to": rid,
                        "type": "NICAttachedToVM",
                        "category": "Physical",
                        "style": "solid"
                    })

        # --- Rule: Subnet -> NSG (Logical/Association) ---
        if rtype == 'microsoft.network/networksecuritygroups':
            # NSG -> Subnet
            associated_subnets = props.get('subnets', [])
            for sn_ref in associated_subnets:
                 relationships.append({
                    "from": rid,
                    "to": sn_ref['id'].lower(),
                    "type": "SecuredBy",
                    "category": "Association", # Logical link
                    "style": "dashed",
                    "direction": "BiDirectional"
                })
            # NSG -> NIC
            associated_nics = props.get('networkInterfaces', [])
            for nic_ref in associated_nics:
                 relationships.append({
                    "from": rid,
                    "to": nic_ref['id'].lower(),
                    "type": "SecuredBy",
                    "category": "Association",
                    "style": "dashed"
                })

        # --- Rule: Traffic Flow (LB -> Pool -> VM) ---
        if rtype == 'microsoft.network/loadbalancers' or rtype == 'microsoft.network/applicationgateways':
            # LB -> BackendPool (Internal Containment or Flow?)
            bepools = props.get('backendAddressPools', [])
            for pool in bepools:
                pool_id = pool.get('id').lower()
                relationships.append({
                    "from": rid,
                    "to": pool_id,
                    "type": "Contains",
                    "category": "Physical", 
                    "style": "none"
                })
                
                # Check backend IPs (NICs)
                # Traffic flows from LB Pool -> NIC
                backend_ips = pool.get('properties', {}).get('backendIPConfigurations', [])
                for ip_ref in backend_ips:
                    ip_config_id = ip_ref.get('id').lower()
                    if "/networkinterfaces/" in ip_config_id:
                        nic_id = ip_config_id.split("/ipconfigurations/")[0]
                        relationships.append({
                            "from": pool_id,
                            "to": nic_id,
                            "type": "Traffic",
                            "category": "Traffic",
                            "style": "arrow_solid", # Explicit traffic flow
                            "description": "LoadBalanced"
                        })
                        
    # Additional Pass for PublicIP -> LB/AGW/NIC
    for r in resources:
        if r['type'].lower() == 'microsoft.network/publicipaddresses':
            ip_config = r.get('properties', {}).get('ipConfiguration', {})
            if ip_config:
                linked_id = ip_config.get('id', '').lower()
                # could be nic-ipconfig or lb-frontend-ipconfig
                target_id = None
                if "/networkinterfaces/" in linked_id:
                    target_id = linked_id.split("/ipconfigurations/")[0]
                elif "/loadbalancers/" in linked_id:
                    target_id = linked_id.split("/frontendipconfigurations/")[0]
                elif "/applicationgateways/" in linked_id:
                    target_id = linked_id.split("/frontendipconfigurations/")[0]
                
                if target_id:
                     relationships.append({
                        "from": r['id'].lower(),
                        "to": target_id,
                        "type": "PublicEndpoint",
                        "category": "Traffic",
                        "style": "arrow_solid",
                        "description": "Ingress"
                    })

    topology["relationships"] = relationships

    # Output
    with open(args.output_file, 'w', encoding='utf-8') as f:
        json.dump(topology, f, indent=2, ensure_ascii=False)

if __name__ == "__main__":
    main()
