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

### 1. Azure Cloud Shell Setup (Important!)
This tool generates the topology data using a shell script, so you **MUST use the Bash environment** in Azure Cloud Shell, NOT PowerShell.

1.  Open **[Azure Cloud Shell](https://shell.azure.com)**.
2.  If prompted, select **Bash** (not PowerShell).
3.  **Mount Storage**: You must create a storage account to save the generated files.
    *   Select "Mount Storage" (스토리지 계정 탑재).
    ![Mount Storage](docs/images/cloud-shell-mount-storage.png)
    *   Select "Create new storage account" (Microsoft에서 사용자의 스토리지 계정을 만듭니다).
    ![Create Storage](docs/images/cloud-shell-create-storage.png)

### 2. Run Generation Script

You can choose one of the following methods to run the script.

#### Option A: One-Liner (Recommended)
Just copy and paste the line below into your Cloud Shell terminal. It will download the necessary scripts and run them automatically.

1.  **Open Cloud Shell**: [![Open in Cloud Shell](https://img.shields.io/static/v1?label=Azure&message=Open+Cloud+Shell&color=0078D4&logo=microsoftazure)](https://shell.azure.com)
2.  **Execute Command**:
    ```bash
    bash <(curl -s https://raw.githubusercontent.com/asomi7007/Azure-Resource-Topology-Auto-Generator/master/scripts/generate-topology.sh)
    ```

#### Option B: Manual Upload
If you prefer to review the scripts before running, you can manually upload them.

1.  **Download Scripts**: Download `scripts/generate-topology.sh` and `scripts/parse-relations.py` from this repository to your PC.
2.  **Upload to Cloud Shell**:
    *   Click the **"Manage files"** icon -> **"Upload"**.
    ![File Share](docs/images/cloud-shell-file-share.png)
3.  **Run**:
    ```bash
    chmod +x generate-topology.sh
    ./generate-topology.sh
    ```

### 3. Download Result
1.  Follow the script prompts to select your Subscription and Resource Group.
2.  The script will generate a file named `topology.json`.
3.  **Download the file**:
    *   Type `download topology.json` in the terminal to save it to your local computer.
    *   Alternatively, use the **"Manage files"** menu -> **"Download"**.
    ![File Share](docs/images/cloud-shell-file-share.png)

### 4. Generate Diagram (server)
1.  **Clone & Run Local Server**:
    ```bash
    git clone https://github.com/asomi7007/Azure-Resource-Topology-Auto-Generator.git
    cd Azure-Resource-Topology-Auto-Generator
    python -m venv venv
    venv\Scripts\activate  # Mac/Linux: source venv/bin/activate
    pip install -r server/requirements.txt
    python server/main.py
    ```
2.  Open `http://localhost:8000` in your browser.
3.  Upload the `topology.json` file.
4.  **Download your Topology** (PPTX / PNG).
