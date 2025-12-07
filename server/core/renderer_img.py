from PIL import Image, ImageDraw, ImageFont
import os
from .icon_manager import IconManager

def generate_image_file(layout_nodes, relationships, output_path):
    # 0. Init Icon Manager
    icon_mgr = IconManager()

    # 1. Calculate Canvas Size & Map
    node_map = {n['id'].lower(): n for n in layout_nodes}
    
    max_w = 0
    max_h = 0
    for n in layout_nodes:
        r = n['x'] + n['w']
        b = n['y'] + n['h']
        if r > max_w: max_w = r
        if b > max_h: max_h = b
            
    width = int(max_w + 200)
    height = int(max_h + 200)
    
    # 2. Draw
    im = Image.new('RGB', (width, height), (255, 255, 255))
    draw = ImageDraw.Draw(im)
    
    try:
        font = ImageFont.truetype("arial.ttf", 10)
        title_font = ImageFont.truetype("arial.ttf", 11, encoding="unic")
    except IOError:
        font = ImageFont.load_default()
        title_font = ImageFont.load_default()
    
    # Draw Lines (Edges) FIRST (so they are behind icons)
    for rel in relationships:
        src_id = rel['from'].lower()
        dst_id = rel['to'].lower()
        
        if src_id in node_map and dst_id in node_map:
            src = node_map[src_id]
            dst = node_map[dst_id]
            
            # Center points
            x1 = src['x'] + src['w']/2
            y1 = src['y'] + src['h']/2
            x2 = dst['x'] + dst['w']/2
            y2 = dst['y'] + dst['h']/2
            
            category = rel.get('category', 'Physical')
            
            color = (150, 150, 150)
            width_px = 1
            
            if category == 'Traffic':
                color = (0, 180, 0) # Green
                width_px = 2
            elif category == 'Association':
                color = (255, 140, 0) # Orange
                width_px = 1
            elif category == 'Physical':
                # VNet -> Subnet -> VM lines
                color = (0, 120, 212) # Blueish
                width_px = 2
                
            draw.line([x1, y1, x2, y2], fill=color, width=width_px)
            
            # Draw Arrow if Traffic
            if category == 'Traffic':
                draw.ellipse([x2-3, y2-3, x2+3, y2+3], fill=color)

    # Draw Nodes (Icons)
    for node in layout_nodes:
        x, y, w, h = node['x'], node['y'], node['w'], node['h']
        res_type = node['resource']['type'].lower()
        
        # Icon Size
        target_size = 48
        
        # Get Icon
        icon = icon_mgr.get_icon_image(res_type, target_size, target_size)
        
        # Center in Node Box
        ix = int(x + (w - target_size)/2)
        iy = int(y)
        
        if icon:
            im.paste(icon, (ix, iy), icon)
        else:
            # Fallback Box
            draw.rectangle([ix, iy, ix+target_size, iy+target_size], fill=(200,200,200))
            
        # Draw Text
        text = node['resource']['name']
        if len(text) > 15: text = text[:12] + "..."
        
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        tx = x + (w - tw)/2
        
        draw.text((tx, iy + target_size + 5), text, fill=(0,0,0), font=font)
        
        # Optional: Label Resource Type (small) below
        # type_short = res_type.split('/')[-1]
        # draw.text((x, iy + target_size + 15), type_short, fill=(100,100,100), font=font)

    im.save(output_path)
