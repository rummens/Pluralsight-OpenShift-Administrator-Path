"""
Backend service tests.

HTTP behaviour + span emission via InMemorySpanExporter added
on top of the already-initialised TracerProvider.
"""
import os
import time
import pytest

# Trigger OTEL setup in app.py with a dummy endpoint (no real server).
# BatchSpanProcessor will silently fail to connect; that is fine for tests.
os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://localhost:14999"
os.environ["CHECKOUT_DELAY_MS"] = "50"  # keep tests fast

import app as backend  # noqa: E402  (env must be set before import)

from opentelemetry import trace
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

# Attach an in-memory exporter so we can inspect spans without a real collector.
_mem = InMemorySpanExporter()
trace.get_tracer_provider().add_span_processor(SimpleSpanProcessor(_mem))


@pytest.fixture(autouse=True)
def clear_spans():
    _mem.clear()
    yield


@pytest.fixture
def client():
    backend.app.config["TESTING"] = True
    return backend.app.test_client()


# ── HTTP behaviour ────────────────────────────────────────────────────────────

def test_health_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert b"ok" in r.data


def test_checkout_returns_accepted(client):
    r = client.get("/checkout")
    assert r.status_code == 200
    assert b"order accepted" in r.data


def test_checkout_respects_delay(client):
    t0 = time.time()
    client.get("/checkout")
    elapsed_ms = (time.time() - t0) * 1000
    # CHECKOUT_DELAY_MS=50, jitter ±50 → minimum ~0 ms, but should be under 200 ms
    assert elapsed_ms < 500, f"checkout took {elapsed_ms:.0f} ms — unexpectedly slow"


# ── Span emission ─────────────────────────────────────────────────────────────

def test_process_order_span_created(client):
    client.get("/checkout")
    names = [s.name for s in _mem.get_finished_spans()]
    assert any("process-order" in n for n in names), \
        f"process-order span missing; got: {names}"


def test_process_order_span_attributes(client):
    client.get("/checkout")
    spans = [s for s in _mem.get_finished_spans() if s.name == "process-order"]
    assert spans, "no process-order span"
    attrs = spans[0].attributes
    assert "checkout.items" in attrs
    assert "checkout.delay_ms" in attrs
    assert 1 <= attrs["checkout.items"] <= 5


def test_flask_server_span_created(client):
    client.get("/checkout")
    names = [s.name for s in _mem.get_finished_spans()]
    # FlaskInstrumentor creates a span named after the HTTP method + route
    assert any("GET" in n or "checkout" in n for n in names), \
        f"no Flask server span; got: {names}"


def test_service_name_in_resource(client):
    client.get("/checkout")
    spans = _mem.get_finished_spans()
    assert spans
    resource_attrs = spans[0].resource.attributes
    assert resource_attrs.get("service.name") == "globomantics-checkout"
