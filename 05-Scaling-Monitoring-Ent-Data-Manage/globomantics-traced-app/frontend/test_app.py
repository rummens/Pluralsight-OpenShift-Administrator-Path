"""
Frontend service tests.

HTTP behaviour + span emission. The backend HTTP call is mocked so tests
run without a real backend service.
"""
import os
import pytest
from unittest.mock import patch, MagicMock

os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://localhost:14999"
os.environ["CHECKOUT_BACKEND_URL"] = "http://mock-backend:8080"

import app as frontend  # noqa: E402

from opentelemetry import trace
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

_mem = InMemorySpanExporter()
trace.get_tracer_provider().add_span_processor(SimpleSpanProcessor(_mem))


@pytest.fixture(autouse=True)
def clear_spans():
    _mem.clear()
    yield


@pytest.fixture
def client():
    frontend.app.config["TESTING"] = True
    return frontend.app.test_client()


def _mock_backend_ok():
    resp = MagicMock()
    resp.status_code = 200
    resp.text = "order accepted"
    return resp


def _mock_backend_error():
    resp = MagicMock()
    resp.status_code = 503
    resp.text = "backend unavailable"
    return resp


# ── HTTP behaviour ────────────────────────────────────────────────────────────

def test_health_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert b"ok" in r.data


def test_index_serves_html(client):
    r = client.get("/")
    assert r.status_code == 200
    assert b"html" in r.data.lower()


def test_checkout_proxies_backend(client):
    with patch("requests.get", return_value=_mock_backend_ok()):
        r = client.get("/checkout")
    assert r.status_code == 200
    assert b"order accepted" in r.data


def test_checkout_propagates_backend_error(client):
    with patch("requests.get", return_value=_mock_backend_error()):
        r = client.get("/checkout")
    assert r.status_code == 503


def test_checkout_handles_backend_exception(client):
    with patch("requests.get", side_effect=ConnectionError("refused")):
        r = client.get("/checkout")
    assert r.status_code == 502


def test_unknown_path_404(client):
    r = client.get("/does-not-exist.html")
    assert r.status_code == 404


# ── Span emission ─────────────────────────────────────────────────────────────

def test_checkout_span_created(client):
    with patch("requests.get", return_value=_mock_backend_ok()):
        client.get("/checkout")
    names = [s.name for s in _mem.get_finished_spans()]
    assert any("checkout" in n.lower() or "GET" in n for n in names), \
        f"no checkout span; got: {names}"


def test_service_name_in_resource(client):
    with patch("requests.get", return_value=_mock_backend_ok()):
        client.get("/checkout")
    spans = _mem.get_finished_spans()
    assert spans
    assert spans[0].resource.attributes.get("service.name") == "globomantics-web"
