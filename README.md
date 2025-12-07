# Azure Resource Topology Auto-Generator (ARTAG)

A tool to automatically scan Azure Resource Groups and generate editable Topology Diagrams (PPTX/PNG) using official Azure Icons.

## Features
-   **One-Liner Scan**: Uses Azure Cloud Shell (`az graph`, `az resource`) to scan connectivity.
-   **Graph Layout**: visualizes VNet -> Subnet -> Resource hierarchy with connected lines.
-   **Official Icons**: Dynamically maps Azure Public Service Icons (SVG) to resources.
-   **Traffic Flow**: Distinguishes between Physical containment, Traffic flow (LoadBalancer), and Association links.
-   **Editable Output**: Generates `.pptx` where every icon and line is a separate editable object.

## Prerequisites
-   Azure CLI (or Cloud Shell)
-   Python 3.9+
-   (Optional) Azure Public Service Icons downloaded to `Azure_Public_Service_Icons/Icons`.

## Installation

1.  Clone this repository.
2.  Install dependencies:
    ```bash
    python -m venv venv
    source venv/bin/activate  # Windows: venv\Scripts\activate
    pip install -r server/requirements.txt
    ```
3.  Download [Azure Public Service Icons](https://learn.microsoft.com/en-us/azure/architecture/icons/) and extract to:
    `Azure_Public_Service_Icons/Icons`

## Usage

### 1. Start Server
```bash
python server/main.py
```
Server runs at `http://localhost:8000`.

### 2. Generate Topology (Cloud Shell)
Copy `scripts/generate-topology.sh` and `scripts/parse-relations.py` to your Azure Cloud Shell.
```bash
chmod +x generate-topology.sh
./generate-topology.sh
```
Follow the prompts to select a Resource Group. Only `topology.json` is sent to the server (no credentials).

### 3. View Results
The script will provide a download link or you can upload the JSON via the Web UI to get your PPTX/PNG.
