import os
import re
from pathlib import Path
from flask import Flask, send_from_directory, abort, Response

BASE_DIR = Path(__file__).resolve().parent
WEB_PAGES_DIR = (BASE_DIR / "globomantics-asset-bundle" / "web-pages").resolve()

app = Flask(__name__, static_folder=None)

# Set variant via environment variable, e.g. APP_VARIANT=v2
APP_VARIANT = os.getenv("APP_VARIANT", "v3")


def inject_variant_banner(html_text: str, variant: str) -> str:
    """Insert a small, obvious banner into HTML just after the <body> tag."""
    banner = (
        f"<div style=\"position:fixed;left:0;top:0;"
        f"background:#ffcc00;color:#000;padding:6px 10px;z-index:9999;"
        f"font-weight:bold;\">Variant: {variant}</div>"
    )
    # Find the first <body ...> tag and inject after the closing '>'
    m = re.search(r"(<body[^>]*>)", html_text, flags=re.IGNORECASE)
    if m:
        return html_text[: m.end()] + banner + html_text[m.end() :]
    # Fallback: prepend if no body tag found
    return banner + html_text


@app.route("/")
def index():
    index_path = WEB_PAGES_DIR / "index.html"
    if not index_path.exists():
        abort(404)
    if APP_VARIANT == "v1":
        return send_from_directory(str(WEB_PAGES_DIR), "index.html")
    content = index_path.read_text(encoding="utf-8")
    modified = inject_variant_banner(content, APP_VARIANT)
    return Response(modified, mimetype="text/html")


@app.route("/<path:filename>")
def serve_file(filename):
    requested = (WEB_PAGES_DIR / filename).resolve()
    if not str(requested).startswith(str(WEB_PAGES_DIR)) or not requested.exists():
        abort(404)
    # For HTML files, inject the banner when variant != v1
    if requested.suffix.lower() == ".html" and APP_VARIANT != "v1":
        content = requested.read_text(encoding="utf-8")
        modified = inject_variant_banner(content, APP_VARIANT)
        return Response(modified, mimetype="text/html")
    relative = requested.relative_to(WEB_PAGES_DIR)
    return send_from_directory(str(WEB_PAGES_DIR), str(relative))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)