# Pluralsight-OpenShift-Fundamentals-and-Workload-Deployment

This repository contains companion material for the Pluralsight course *OpenShift\-Fundamentals\-and\-Workload\-Deployment*.  
TODO: Add a link to the Pluralsight course.

## Contents

- `globomantics-asset-bundle/web-pages` — static HTML pages used by the demo webapp (includes `index.html`).
- `globomantics-webapp` — minimal Flask app that serves the static files.
- `requirements.txt` — Python dependencies.
- `Dockerfile` — image definition using a slim Python base and a non\-root user.
- `build-and-push.sh` — script to build multi\-arch images and push to GitHub Container Registry.

## Quick start (local)

1. Create and activate a virtual environment:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   ```
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Run the app:
   ```bash
   python globomantics-webapp/app.py
   ```
4. Open a browser and navigate to `http://localhost:8080`.

## Build and push multi-arch image
1. Make sure you are logged in to GitHub Container Registry:
   ```bash
    export CR_PAT=<your-token>
    ```
2. Run the build and push script:
   ```bash
   ./build-and-push.sh YOUR_GITHUB_USERNAME
   ```
## Notes
The Dockerfile creates a non-root user and runs the app with gunicorn on port 8080.
The Flask app safely resolves requested paths to prevent directory traversal when serving static files.