import math
import os
import re
from pathlib import Path
from flask import Flask, send_from_directory, abort, Response, request, g, jsonify
import time
from typing import Optional
import psycopg2
import logging
import sys
import threading

BASE_DIR = Path(__file__).resolve().parent
WEB_PAGES_DIR = (BASE_DIR / "globomantics-asset-bundle" / "web-pages").resolve()

app = Flask(__name__, static_folder=None)

# Configure basic logging to stdout so logs appear in container output
LOG_LEVEL_NAME = os.getenv("LOG_LEVEL", "INFO").upper()
LOG_LEVEL = getattr(logging, LOG_LEVEL_NAME, logging.INFO)
REQUEST_LOGGING = os.getenv("REQUEST_LOGGING", "false").lower() in ("1", "true", "yes")

logging.basicConfig(stream=sys.stdout, level=LOG_LEVEL, format='%(asctime)s %(levelname)s %(name)s: %(message)s')
# Ensure gunicorn and werkzeug use the same handlers (so their logs appear in stdout)
for logger_name in ("gunicorn.error", "gunicorn.access", "werkzeug"):
    logger = logging.getLogger(logger_name)
    logger.handlers = logging.root.handlers
    logger.setLevel(LOG_LEVEL)

# Tie Flask's app.logger to the root handlers as well
app.logger.handlers = logging.root.handlers
app.logger.setLevel(LOG_LEVEL)

# If request logging is enabled, add middleware to log each request with timing and status
if REQUEST_LOGGING:
    @app.before_request
    def _log_request_start():
        g._req_start_time = time.time()

    @app.after_request
    def _log_request_end(response):
        try:
            start = getattr(g, '_req_start_time', None)
            duration = (time.time() - start) * 1000.0 if start else 0.0
            remote = request.remote_addr or '-'
            method = request.method
            path = request.path
            status = response.status_code
            app.logger.info(f"{remote} {method} {path} {status} {duration:.2f}ms")
        except Exception:
            app.logger.exception("Failed to log request")
        return response

# Control debug mode via environment variable; default is False in containers
FLASK_DEBUG = os.getenv("FLASK_DEBUG", "false").lower() in ("1", "true", "yes")

# Set variant via environment variable, e.g. APP_VARIANT=v2
APP_VARIANT = os.getenv("APP_VARIANT", "v3")

# New: control whether DB is required at startup. If true and DB envs are missing or
# the connection fails, startup will abort.
# Set e.g. DB_REQUIRED=true to make DB required.
DB_REQUIRED = os.getenv("DB_REQUIRED", "false").lower() in ("1", "true", "yes")

if DB_REQUIRED:
    app.logger.info("DB_REQUIRED is set to True: missing DB envs or connection failure will abort startup")
else:
    app.logger.info("DB_REQUIRED is set to False: missing DB envs or connection failure will be logged but startup will continue")

# optional startup delay (seconds). Useful to simulate slow-starting apps.
STARTUP_DELAY = int(os.getenv("STARTUP_DELAY", "0"))

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
    else:
        app.logger.info("All DB environment variables are set: " + ", ".join(f"{k}=***" for k in db_keys))

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


# Health failure toggle (thread-safe)
_health_fail = False
_health_fail_reason = ""
_health_fail_lock = threading.Lock()

@app.route("/health")
def health():
    # Return unhealthy (503) if the failure toggle has been set via /health/fail
    with _health_fail_lock:
        if _health_fail:
            reason = _health_fail_reason or "forced-failure"
            app.logger.warning(f"/health returning 503 due to forced failure: {reason}")
            return Response(f"unhealthy: {reason}", status=503, mimetype="text/plain")
    return Response("ok", status=200, mimetype="text/plain")


@app.route("/health/fail", methods=["POST"])
def health_fail():
    """Trigger the health endpoint to return an error. Accepts optional ?reason=..."""
    reason = request.args.get("reason") or request.form.get("reason") or "manual"
    global _health_fail, _health_fail_reason
    with _health_fail_lock:
        _health_fail = True
        _health_fail_reason = reason
    app.logger.warning(f"/health/fail invoked: reason={reason}")
    return Response(f"health failure set: {reason}", status=200, mimetype="text/plain")


@app.route("/health/ok", methods=["POST"])
def health_ok():
    """Clear the health failure so /health returns ok again."""
    global _health_fail, _health_fail_reason
    with _health_fail_lock:
        _health_fail = False
        _health_fail_reason = ""
    app.logger.info("/health/ok invoked: health restored")
    return Response("health restored", status=200, mimetype="text/plain")


def is_prime(n: int) -> bool:
    """Very inefficient prime check (on purpose)."""
    if n < 2:
        return False
    for i in range(2, int(math.sqrt(n)) + 1):
        if n % i == 0:
            return False
    return True


def count_primes(limit: int) -> int:
    """Count prime numbers up to 'limit' (CPU intensive)."""
    count = 0
    for number in range(2, limit):
        if is_prime(number):
            count += 1
    return count


@app.route("/heavy")
def heavy():
    """
    Example:
    /heavy?limit=50000

    Increase limit for more CPU usage.
    """
    try:
        limit = int(request.args.get("limit", 90000))
    except ValueError:
        return jsonify({"error": "Invalid limit parameter"}), 400

    start = time.time()
    result = count_primes(limit)
    duration = time.time() - start

    return jsonify({
        "limit": limit,
        "prime_count": result,
        "duration_seconds": duration
    })

app.logger.info(f"Delaying startup for {STARTUP_DELAY} seconds")
time.sleep(STARTUP_DELAY)

# Initialize DB connection
init_db_connection()

if __name__ == "__main__":
    # When running directly, avoid the werkzeug reloader which can create a control
    # socket and cause permission errors in restrictive container environments.
    # Use FLASK_DEBUG to control debug mode; reloader disabled for safety.
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), debug=FLASK_DEBUG, use_reloader=False)
