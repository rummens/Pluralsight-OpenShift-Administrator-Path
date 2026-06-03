import os
import sys
import logging
from pathlib import Path

import requests
from flask import Flask, send_from_directory, abort, Response

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

BASE_DIR = Path(__file__).resolve().parent
WEB_PAGES_DIR = (BASE_DIR / "globomantics-asset-bundle" / "web-pages").resolve()

app = Flask(__name__, static_folder=None)

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
app.logger.handlers = logging.root.handlers
app.logger.setLevel(logging.INFO)

SERVICE_NAME = os.getenv("OTEL_SERVICE_NAME", "globomantics-web")
OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
CHECKOUT_BACKEND_URL = os.getenv("CHECKOUT_BACKEND_URL", "http://globomantics-checkout:8080")

if OTLP_ENDPOINT:
    resource = Resource.create({"service.name": SERVICE_NAME})
    provider = TracerProvider(resource=resource)
    # Strip scheme so grpc.insecure_channel gets a bare host:port
    grpc_endpoint = OTLP_ENDPOINT.removeprefix("http://").removeprefix("https://")
    exporter = OTLPSpanExporter(endpoint=grpc_endpoint, insecure=True)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    FlaskInstrumentor().instrument_app(app)
    RequestsInstrumentor().instrument()
    app.logger.info("OTLP tracing enabled: endpoint=%s service=%s", OTLP_ENDPOINT, SERVICE_NAME)
else:
    app.logger.info("OTEL_EXPORTER_OTLP_ENDPOINT not set — tracing disabled")


@app.route("/checkout")
def checkout():
    try:
        resp = requests.get(f"{CHECKOUT_BACKEND_URL}/checkout", timeout=10)
        return Response(resp.text, status=resp.status_code, mimetype="text/plain")
    except Exception as exc:
        app.logger.error("checkout backend error: %s", exc)
        return Response(f"backend error: {exc}", status=502, mimetype="text/plain")


@app.route("/health")
def health():
    return Response("ok", status=200, mimetype="text/plain")


@app.route("/")
def index():
    index_path = WEB_PAGES_DIR / "index.html"
    if not index_path.exists():
        abort(404)
    return send_from_directory(str(WEB_PAGES_DIR), "index.html")


@app.route("/<path:filename>")
def serve_file(filename):
    requested = (WEB_PAGES_DIR / filename).resolve()
    if not str(requested).startswith(str(WEB_PAGES_DIR)) or not requested.exists():
        abort(404)
    relative = requested.relative_to(WEB_PAGES_DIR)
    return send_from_directory(str(WEB_PAGES_DIR), str(relative))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), use_reloader=False)
