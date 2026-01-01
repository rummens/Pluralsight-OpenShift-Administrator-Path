from pathlib import Path
from flask import Flask, send_from_directory, abort

# Resolve the web-pages directory relative to this file:
# expects project layout where globomantics-webapp is sibling to globomantics-asset-bundle
BASE_DIR = Path(__file__).resolve().parent
WEB_PAGES_DIR = (BASE_DIR / "globomantics-asset-bundle" / "web-pages").resolve()

app = Flask(__name__, static_folder=None)


@app.route("/")
def index():
    index_path = WEB_PAGES_DIR / "index.html"
    if not index_path.exists():
        abort(404)
    return send_from_directory(str(WEB_PAGES_DIR), "index.html")


@app.route("/<path:filename>")
def serve_file(filename):
    # Prevent directory traversal by resolving and ensuring it stays inside WEB_PAGES_DIR
    requested = (WEB_PAGES_DIR / filename).resolve()
    if not str(requested).startswith(str(WEB_PAGES_DIR)) or not requested.exists():
        abort(404)
    # send_from_directory expects the filename relative to the directory
    relative = requested.relative_to(WEB_PAGES_DIR)
    return send_from_directory(str(WEB_PAGES_DIR), str(relative))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)