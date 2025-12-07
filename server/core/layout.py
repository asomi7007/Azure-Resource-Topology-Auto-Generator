from typing import List, Dict, Any, Tuple

# Constants for Layout
ICON_WIDTH = 64
ICON_HEIGHT = 64
PADDING = 40
LABEL_HEIGHT = 20
Grid_Columns = 4

class LayoutEngine:
    def __init__(self, topology: Dict[str, Any]):
        self.topology = topology
        self.resources = topology.get("resources", [])
        self.relationships = topology.get("relationships", [])
        
        # Output: Map of ResourceID -> {x, y, w, h, parentId, children: []}
        self.layout_map = {}
        
    def calculate_layout(self):
        # 1. Structure the data hierarchically
        # VNet -> Subnet -> Resources
        # Others (orphans)
        
        vnets = [r for r in self.resources if r['type'].lower() == 'microsoft.network/virtualnetworks']
        processed_ids = set()
        
        # We will build a tree structure for layout calculation
        root_nodes = []
        
        # Helper: Find direct children based on 'Contains' relationship or specific rules
        for vnet in vnets:
            v_node = self._build_node(vnet)
            processed_ids.add(vnet['id'].lower())
            
            # Find subnets
            # 1. Check relationships "VNet Contains Subnet"
            # 2. Check "Attached" from Subnet to NIC (Reverse) - implies subnets
            
            # Get subnets strictly inside this VNet
            child_subnets = self._find_children(vnet['id'], "Contains", "microsoft.network/virtualnetworks/subnets")
            
            for sn_id in child_subnets:
                 sn_res = self._find_resource(sn_id)
                 if sn_res:
                     sn_node = self._build_node(sn_res)
                     processed_ids.add(sn_id.lower())
                     
                     # Find resources inside Subnet
                     # Usually: NICs are "Attached" to Subnet. We can treat them as visually inside or linked.
                     # "Attached" relationship: From Subnet -> To NIC.
                     # Let's verify our parser logic. 
                     # Parser: "from: subnet, to: nic, type: Attached"
                     
                     nic_ids = self._find_children(sn_id, "Attached", None)
                     for nic_id in nic_ids:
                         nic_res = self._find_resource(nic_id)
                         if nic_res:
                             nic_node = self._build_node(nic_res)
                             processed_ids.add(nic_id.lower())
                             
                             # Find VMs attached to this NIC
                             # Parser: "from: nic, to: vm, type: NICAttachedToVM"
                             vm_ids = self._find_children(nic_id, "NICAttachedToVM", None)
                             for vm_id in vm_ids:
                                 vm_res = self._find_resource(vm_id)
                                 if vm_res:
                                      vm_node = self._build_node(vm_res)
                                      processed_ids.add(vm_id.lower())
                                      nic_node['children'].append(vm_node)
                                      
                             sn_node['children'].append(nic_node)
                     
                     v_node['children'].append(sn_node)
            
            root_nodes.append(v_node)
            
        # Handle Orphans (Not processed yet)
        # e.g. Random LBs, Public IPs not linked yet
        for r in self.resources:
            if r['id'].lower() not in processed_ids:
                root_nodes.append(self._build_node(r))
                
        # 2. Calculate coordinates (Recursively)
        current_y = 0
        MAX_WIDTH = 0
        
        for node in root_nodes:
            w, h = self._layout_node_recursive(node, 0, current_y)
            current_y += h + PADDING
            if w > MAX_WIDTH:
                MAX_WIDTH = w
                
        return root_nodes

    def _build_node(self, resource):
        return {
            "resource": resource,
            "id": resource['id'],
            "type": resource['type'],
            "children": [],
            "x": 0, "y": 0, "w": 0, "h": 0
        }

    def _find_children(self, parent_id, rel_type, child_type_filter):
        children = []
        for rel in self.relationships:
            if rel['from'].lower() == parent_id.lower() and rel['type'] == rel_type:
                # Optional type check
                if child_type_filter:
                    # Look up the target resource to check type
                    target = self._find_resource(rel['to'])
                    if target and target['type'].lower() == child_type_filter.lower():
                        children.append(rel['to'])
                else:
                    children.append(rel['to'])
        return children

    def _find_resource(self, rid):
        for r in self.resources:
            if r['id'].lower() == rid.lower():
                return r
        return None

    def _layout_node_recursive(self, node, x_offset, y_offset):
        # If leaf node
        if not node['children']:
            node['x'] = x_offset
            node['y'] = y_offset
            node['w'] = ICON_WIDTH + 20
            node['h'] = ICON_HEIGHT + LABEL_HEIGHT + 10
            return node['w'], node['h']
            
        # If container node (VNet, Subnet)
        # Layout children in a grid
        child_max_h = 0
        child_max_w = 0
        
        cur_x = x_offset + PADDING
        cur_y = y_offset + PADDING + 40 # Header space
        
        cols = 0
        row_h = 0
        
        for child in node['children']:
            cw, ch = self._layout_node_recursive(child, cur_x, cur_y)
            
            cur_x += cw + PADDING
            row_h = max(row_h, ch)
            cols += 1
            
            if cols >= Grid_Columns:
                cur_x = x_offset + PADDING
                cur_y += row_h + PADDING
                cols = 0
                row_h = 0
                
        # Final dimensions for this container
        width = max((ICON_WIDTH + PADDING) * Grid_Columns, cur_x - x_offset) + PADDING
        if cols == 0 and len(node['children']) > 0: # Just finished a row
             height = cur_y
        else:
             height = cur_y + row_h + PADDING
             
        # Normalize relative to y_offset
        height = height - y_offset
        
        node['x'] = x_offset
        node['y'] = y_offset
        node['w'] = width
        node['h'] = height
        
        return width, height
