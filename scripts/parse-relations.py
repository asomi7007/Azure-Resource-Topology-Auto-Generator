#!/usr/bin/env python3
"""
Azure Resource Topology Parser
Parses raw Azure Resource Graph output and generates topology JSON.
"""

import json
import sys
import argparse


def main():
    parser = argparse.ArgumentParser(description='Parse Azure Resources to Topology JSON')
    parser.add_argument('input_file', help='Input raw JSON file from az graph query')
    parser.add_argument('output_file', help='Output topology JSON file')
    parser.add_argument('--rg', help='Resource Group Name(s)', required=True)
    args = parser.parse_args()

    print(f"Parsing {args.input_file}...")

    # Load raw data
    try:
        with open(args.input_file, 'r', encoding='utf-8') as f:
            raw_data = json.load(f)
    except FileNotFoundError:
        print(f"[Error] File not found: {args.input_file}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"[Error] Invalid JSON: {e}")
        sys.exit(1)

    # Handle az graph query output format
    # az graph query wraps results in: { "data": [...], "skip_token": null, ... }
    if isinstance(raw_data, dict) and 'data' in raw_data:
        resources = raw_data['data']
    elif isinstance(raw_data, list):
        resources = raw_data
    else:
        print(f"[Error] Unexpected data format: {type(raw_data)}")
        resources = []

    # Filter valid resources (must be dict with 'id' key)
    valid_resources = [r for r in resources if isinstance(r, dict) and 'id' in r]
    print(f"Loaded {len(valid_resources)} valid resources.")

    if len(valid_resources) == 0:
        print("[Warning] No valid resources to process.")

    # Initialize topology
    topology = {
        "resourceGroup": args.rg,
        "resources": [],
        "relationships": []
    }

    # Build resource map for quick lookup
    resource_map = {r['id'].lower(): r for r in valid_resources}

    # Process resources
    for r in valid_resources:
        node = {
            "id": r.get('id', ''),
            "name": r.get('name', 'Unknown'),
            "type": r.get('type', 'Unknown'),
            "location": r.get('location', ''),
            "tags": r.get('tags') or {},
            "properties": r.get('properties') or {}
        }
        topology["resources"].append(node)

    # Process relationships
    relationships = []

    for r in valid_resources:
        rid = r['id'].lower()
        rtype = r.get('type', '').lower()
        props = r.get('properties') or {}

        # VNet -> Subnet
        if rtype == 'microsoft.network/virtualnetworks':
            for subnet in props.get('subnets') or []:
                subnet_id = subnet.get('id')
                if subnet_id:
                    relationships.append({
                        "from": rid,
                        "to": subnet_id.lower(),
                        "type": "Contains",
                        "category": "Physical"
                    })
                    # Add subnet as node if not exists
                    if subnet_id.lower() not in resource_map:
                        topology["resources"].append({
                            "id": subnet_id,
                            "name": subnet.get('name', 'subnet'),
                            "type": "Microsoft.Network/virtualNetworks/subnets",
                            "location": r.get('location', ''),
                            "properties": subnet.get('properties') or {}
                        })

        # NIC -> Subnet
        if rtype == 'microsoft.network/networkinterfaces':
            for ipconfig in props.get('ipConfigurations') or []:
                subnet_ref = (ipconfig.get('properties') or {}).get('subnet') or {}
                subnet_id = subnet_ref.get('id')
                if subnet_id:
                    relationships.append({
                        "from": subnet_id.lower(),
                        "to": rid,
                        "type": "Attached",
                        "category": "Physical"
                    })

        # VM -> NIC
        if rtype == 'microsoft.compute/virtualmachines':
            net_profile = props.get('networkProfile') or {}
            for nic_ref in net_profile.get('networkInterfaces') or []:
                nic_id = nic_ref.get('id')
                if nic_id:
                    relationships.append({
                        "from": nic_id.lower(),
                        "to": rid,
                        "type": "AttachedTo",
                        "category": "Physical"
                    })

        # NSG -> Subnet/NIC
        if rtype == 'microsoft.network/networksecuritygroups':
            for subnet_ref in props.get('subnets') or []:
                if 'id' in subnet_ref:
                    relationships.append({
                        "from": rid,
                        "to": subnet_ref['id'].lower(),
                        "type": "SecuredBy",
                        "category": "Association"
                    })
            for nic_ref in props.get('networkInterfaces') or []:
                if 'id' in nic_ref:
                    relationships.append({
                        "from": rid,
                        "to": nic_ref['id'].lower(),
                        "type": "SecuredBy",
                        "category": "Association"
                    })

        # Load Balancer -> Backend Pool -> NIC
        if rtype in ['microsoft.network/loadbalancers', 'microsoft.network/applicationgateways']:
            for pool in props.get('backendAddressPools') or []:
                pool_id = pool.get('id')
                if pool_id:
                    relationships.append({
                        "from": rid,
                        "to": pool_id.lower(),
                        "type": "Contains",
                        "category": "Physical"
                    })
                    for ip_ref in (pool.get('properties') or {}).get('backendIPConfigurations') or []:
                        ip_id = ip_ref.get('id', '').lower()
                        if '/networkinterfaces/' in ip_id:
                            nic_id = ip_id.split('/ipconfigurations/')[0]
                            relationships.append({
                                "from": pool_id.lower(),
                                "to": nic_id,
                                "type": "Traffic",
                                "category": "Traffic"
                            })

        # Public IP -> NIC/LB
        if rtype == 'microsoft.network/publicipaddresses':
            ip_config = props.get('ipConfiguration') or {}
            linked_id = ip_config.get('id', '').lower()
            target_id = None
            if '/networkinterfaces/' in linked_id:
                target_id = linked_id.split('/ipconfigurations/')[0]
            elif '/loadbalancers/' in linked_id:
                target_id = linked_id.split('/frontendipconfigurations/')[0]
            elif '/applicationgateways/' in linked_id:
                target_id = linked_id.split('/frontendipconfigurations/')[0]
            
            if target_id:
                relationships.append({
                    "from": rid,
                    "to": target_id,
                    "type": "PublicEndpoint",
                    "category": "Traffic"
                })

    topology["relationships"] = relationships

    # Write output
    with open(args.output_file, 'w', encoding='utf-8') as f:
        json.dump(topology, f, indent=2, ensure_ascii=False)

    print(f"Topology saved to {args.output_file}")
    print(f"  - {len(topology['resources'])} resources")
    print(f"  - {len(topology['relationships'])} relationships")


if __name__ == "__main__":
    main()
