from fastapi import FastAPI, UploadFile, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import shutil
import os
import uuid
import json

from fastapi.staticfiles import StaticFiles

app = FastAPI(title="Azure Topology Auto-Generator API")

# Storage config (Local for now)
UPLOAD_DIR = "storage/uploads"
OUTPUT_DIR = "storage/outputs"
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs("server/static", exist_ok=True)

app.mount("/static", StaticFiles(directory="server/static"), name="static")

class TopologyRequest(BaseModel):
    resourceGroup: str
    resources: List[Dict[str, Any]]
    relationships: List[Dict[str, Any]]

# Import Engine (Lazy import to allow main to run even if engine text is not fully ready)
# from core.engine import generate_diagrams

@app.get("/")
def read_root():
    return FileResponse("server/static/index.html")

@app.post("/api/topology/upload")
async def upload_topology(request: TopologyRequest, background_tasks: BackgroundTasks):
    request_id = str(uuid.uuid4())
    
    # 1. Save JSON
    json_path = os.path.join(UPLOAD_DIR, f"{request_id}.json")
    with open(json_path, "w", encoding='utf-8') as f:
        json.dump(request.dict(), f, indent=2)
    
    # 2. Trigger Generation (In background)
    # Background task to generate PNG/PPTX
    background_tasks.add_task(process_topology, request_id, request.dict())
    
    # 3. Return URLs (Optimistic)
    base_url = "http://localhost:8000" # TODO: Configure dynamically
    return {
        "requestId": request_id,
        "status": "Processing",
        "links": {
            "png": f"{base_url}/download/{request_id}/topology.png",
            "pptx": f"{base_url}/download/{request_id}/topology.pptx"
        }
    }

@app.get("/download/{request_id}/{file_type}")
def download_file(request_id: str, file_type: str):
    # file_type: topology.png or topology.pptx
    filename = file_type # simplified
    file_path = os.path.join(OUTPUT_DIR, request_id, filename)
    
    if not os.path.exists(file_path):
        # Check if processing failed or still running
        # For simple UX, return 404 or a placeholder 'processing' image
        raise HTTPException(status_code=404, detail="File not found or still processing")
        
    return FileResponse(file_path)

from core.layout import LayoutEngine
from core.renderer_pptx import generate_pptx_file
from core.renderer_img import generate_image_file

async def process_topology(request_id: str, data: Dict[str, Any]):
    print(f"Processing topology for {request_id}...")
    
    # Create output dir for this request
    req_output_dir = os.path.join(OUTPUT_DIR, request_id)
    os.makedirs(req_output_dir, exist_ok=True)
    
    try:
        # 1. Run Layout Engine
        engine = LayoutEngine(data)
        layout_nodes = engine.calculate_layout()
        
        # 2. Render PNG
        png_path = os.path.join(req_output_dir, "topology.png")
        generate_image_file(layout_nodes, data.get('relationships', []), png_path)
        
        # 3. Render PPTX
        pptx_path = os.path.join(req_output_dir, "topology.pptx")
        generate_pptx_file(layout_nodes, data.get('relationships', []), pptx_path)
            
        print(f"Finished processing {request_id}")
        
    except Exception as e:
        print(f"Error processing {request_id}: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
