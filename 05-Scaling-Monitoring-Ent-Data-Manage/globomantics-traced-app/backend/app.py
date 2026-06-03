import os
import sys
import time
import random
import logging

from flask import Flask, Response

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor

app = Flask(__name__)

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
app.logger.handlers = logging.root.handlers
app.logger.setLevel(logging.INFO)

SERVICE_NAME = os.getenv("OTEL_SERVICE_NAME", "globomantics-checkout")
OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
# Artificial processing delay in milliseconds — makes the backend span
# visibly wider than the frontend span in the trace waterfall view.
CHECKOUT_DELAY_MS = int(os.getenv("CHECKOUT_DELAY_MS", "300"))

if OTLP_ENDPOINT:
    resource = Resource.create({"service.name": SERVICE_NAME})
    provider = TracerProvider(resource=resource)
    grpc_endpoint = OTLP_ENDPOINT.removeprefix("http://").removeprefix("https://")
    exporter = OTLPSpanExporter(endpoint=grpc_endpoint, insecure=True)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    FlaskInstrumentor().instrument_app(app)
    app.logger.info("OTLP tracing enabled: endpoint=%s service=%s", OTLP_ENDPOINT, SERVICE_NAME)
else:
    app.logger.info("OTEL_EXPORTER_OTLP_ENDPOINT not set — tracing disabled")

tracer = trace.get_tracer(__name__)


@app.route("/checkout")
def checkout():
    delay_ms = CHECKOUT_DELAY_MS + random.randint(-50, 50)
    with tracer.start_as_current_span("process-order") as span:
        span.set_attribute("checkout.items", random.randint(1, 5))
        span.set_attribute("checkout.delay_ms", delay_ms)
        time.sleep(delay_ms / 1000.0)
    return Response("order accepted", status=200, mimetype="text/plain")


@app.route("/health")
def health():
    return Response("ok", status=200, mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), use_reloader=False)
