import os
import re
from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM
from PIL import Image
import io

# Valid absolute path to icons
ICON_ROOT = r"C:\Users\asomi\OneDrive - 엘던솔루션\작업용\Azure Resource Topology Auto-Generator\Azure_Public_Service_Icons\Icons"

class IconManager:
    def __init__(self):
        self.icon_cache = {}
        self.path_map = {} # keys normalized -> full path
        self._build_icon_map()

    def _build_icon_map(self):
        """Recursively scans ICON_ROOT and builds a normalized map."""
        if not os.path.exists(ICON_ROOT):
            print(f"[WARN] Icon root not found: {ICON_ROOT}")
            return

        print(f"[INFO] Scanning icons in {ICON_ROOT}...")
        count = 0
        for root, dirs, files in os.walk(ICON_ROOT):
            for file in files:
                if file.lower().endswith('.svg'):
                    full_path = os.path.join(root, file)
                    # Normalize filename to create a key
                    # Remove generic prefixes like "10021-icon-service-" or "00000-"
                    # Key format: "cluster" or "virtualmachine" or "keyvault"
                    
                    # 1. Remove extension
                    name = os.path.splitext(file)[0].lower()
                    
                    # 2. Remove numeric prefix (e.g. 10021- or 00021-)
                    # Regex: Start with digits, then dash/space?
                    clean_name = re.sub(r'^\d+[-_]*', '', name)
                    
                    # 3. Remove common prefixes
                    clean_name = clean_name.replace('icon-service-', '').replace('icon-', '')
                    
                    # 4. Remove dashes/spaces
                    clean_name = clean_name.replace('-', '').replace(' ', '').replace('_', '')
                    
                    # Store mapping (Last write wins, but usually filenames are unique enough in intent)
                    self.path_map[clean_name] = full_path
                    
                    # Also map specific resource types if we can guess
                    if "virtualnetwork" in clean_name: self.path_map['virtualnetworks'] = full_path
                    if "subnet" in clean_name: self.path_map['subnets'] = full_path
                    if "networkinterface" in clean_name: self.path_map['networkinterfaces'] = full_path
                    
                    count += 1
        print(f"[INFO] Loaded {count} icons.")

    def get_icon_path(self, resource_type: str):
        # Resource Type format: "Microsoft.Compute/virtualMachines"
        # We want to match against our normalized keys
        
        # 1. Extract the last part (e.g., virtualMachines)
        parts = resource_type.lower().split('/')
        target_name = parts[-1]
        
        # Normalize target
        target_name = target_name.replace(' ', '').replace('-', '')
        
        # S (plural) handling: "virtualmachines" vs "virtualmachine"
        # Try exact
        if target_name in self.path_map:
            return self.path_map[target_name]
            
        # Try singular
        if target_name.endswith('s') and target_name[:-1] in self.path_map:
            return self.path_map[target_name[:-1]]

        # Try plural
        if target_name + 's' in self.path_map:
            return self.path_map[target_name + 's']

        # Fallback: Search for partial match in keys
        for k, v in self.path_map.items():
            if target_name in k or k in target_name:
                return v
                
        # Final Fallback: Resource Group Icon or Generic
        if 'resourcegroup' in self.path_map:
            return self.path_map['resourcegroup']
            
        return None

    def get_icon_image(self, resource_type: str, width=64, height=64) -> Image.Image:
        """Returns a PIL Image object (PNG format)"""
        cache_key = f"{resource_type}_{width}x{height}"
        if cache_key in self.icon_cache:
            return self.icon_cache[cache_key]
            
        svg_path = self.get_icon_path(resource_type)
        if not svg_path or not os.path.exists(svg_path):
            print(f"[WARN] No icon found for {resource_type}")
            return self._create_placeholder(width, height)
            
        try:
            drawing = svg2rlg(svg_path)
            
            # Scale logic to fit box
            scale_x = width / drawing.width
            scale_y = height / drawing.height
            scale = min(scale_x, scale_y)
            
            # Center it
            drawing.scale(scale, scale)
            # Adjust canvas size? drawing.width/height update doesn't resize the canvas automatically in reportlab sometimes,
            # but renderPM uses the drawing bounds.
            # Let's force a fixed size canvas by creating a new drawing? 
            # Easier: Just render and let PIL resize if needed, OR trust reportlab scale.
            
            png_data = renderPM.drawToString(drawing, fmt='PNG')
            img = Image.open(io.BytesIO(png_data))
            img = img.convert("RGBA")
            
            # Resample if needed to exact W/H?
            # Reportlab render might be arbitrary size. unique scale.
            if img.size != (width, height):
                img = img.resize((width, height), Image.LANCZOS)
                
            self.icon_cache[cache_key] = img
            return img
            
        except Exception as e:
            print(f"[ERR] Failed to convert {svg_path}: {e}")
            return self._create_placeholder(width, height)

    def _create_placeholder(self, w, h):
        # Create a semi-transparent gray box with ? mark
        img = Image.new('RGBA', (w, h), (200, 200, 200, 128))
        return img
