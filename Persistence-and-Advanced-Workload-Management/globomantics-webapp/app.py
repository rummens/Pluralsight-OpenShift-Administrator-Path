import os
import re
from pathlib import Path
from flask import Flask, send_from_directory, abort, Response
import time
from typing import Optional
import psycopg2
import logging
import sys

BASE_DIR = Path(__file__).resolve().parent
WEB_PAGES_DIR = (BASE_DIR / "globomantics-asset-bundle" / "web-pages").resolve()

app = Flask(__name__, static_folder=None)

# Configure basic logging to stdout so logs appear in container output
logging.basicConfig(stream=sys.stdout, level=logging.INFO, format='%(asctime)s %(levelname)s %(name)s: %(message)s')
# Ensure gunicorn and werkzeug use the same handlers (so their logs appear in stdout)
for logger_name in ("gunicorn.error", "gunicorn.access", "werkzeug"):
    logger = logging.getLogger(logger_name)
    logger.handlers = logging.root.handlers
    logger.setLevel(logging.INFO)

# Tie Flask's app.logger to the root handlers as well
app.logger.handlers = logging.root.handlers
app.logger.setLevel(logging.INFO)

# Control debug mode via environment variable; default is False in containers
FLASK_DEBUG = os.getenv("FLASK_DEBUG", "false").lower() in ("1", "true", "yes")

# Set variant via environment variable, e.g. APP_VARIANT=v2
APP_VARIANT = os.getenv("APP_VARIANT", "v3")

# New: control whether DB is required at startup. If true and DB envs are missing or
# the connection fails, startup will abort.
# Set e.g. DB_REQUIRED=true to make DB required.
DB_REQUIRED = os.getenv("DB_REQUIRED", "false").lower() in ("1", "true", "yes")

# optional startup delay (seconds). Useful to simulate slow-starting apps.
STARTUP_DELAY = int(os.getenv("STARTUP_DELAY", "0"))

if DB_REQUIRED:
    app.logger.info("DB_REQUIRED is set to True: missing DB envs or connection failure will abort startup")
else:
    app.logger.info("DB_REQUIRED is set to False: missing DB envs or connection failure will be logged but startup will continue")

def init_db_connection() -> Optional[object]:
    """Validate DB envs and attempt a Postgres connection if present.

    Returns a DB connection object if connected, or None if not connected.
    If DB_REQUIRED is True, missing envs or a failed connection will raise SystemExit
    to stop startup.
    """
    db_keys = ["DB_USER", "DB_PASSWORD", "DB_HOST", "DB_PORT", "DB_NAME"]
    db_envs = {k: os.getenv(k) for k in db_keys}
    missing = [k for k, v in db_envs.items() if not v]
    if missing:
        msg = f"Missing DB environment variables: {', '.join(missing)}"
        if DB_REQUIRED:
            # Fail startup
            raise SystemExit(msg)
        app.logger.info(msg + "; continuing because DB_REQUIRED is not set")
        return None

    # Attempt to connect with a short timeout
    try:
        conn = psycopg2.connect(
            dbname=db_envs["DB_NAME"],
            user=db_envs["DB_USER"],
            password=db_envs["DB_PASSWORD"],
            host=db_envs["DB_HOST"],
            port=int(db_envs["DB_PORT"]),
            connect_timeout=5,
        )
        app.logger.info("Connected to Postgres successfully")
        return conn
    except Exception as e:
        msg = f"Failed to connect to Postgres: {e}"
        if DB_REQUIRED:
            app.logger.critical(msg)
            raise SystemExit(msg)
        app.logger.warning(msg + "; continuing because DB_REQUIRED is not set")
        return None


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


app.logger.info(f"Delaying startup for {STARTUP_DELAY} seconds")
time.sleep(STARTUP_DELAY)

# Initialize DB connection
init_db_connection()

if __name__ == "__main__":
    # When running directly, avoid the werkzeug reloader which can create a control
    # socket and cause permission errors in restrictive container environments.
    # Use FLASK_DEBUG to control debug mode; reloader disabled for safety.
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), debug=FLASK_DEBUG, use_reloader=False)
