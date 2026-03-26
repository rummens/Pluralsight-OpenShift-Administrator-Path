#!/usr/bin/env python3
"""Simple responder service

Returns the application version (from env) and the pod name the app runs in.
Designed to run inside Kubernetes.
"""
from flask import Flask, jsonify, Response
import os

app = Flask(__name__)

# Read version from environment (support VERSION or APP_VERSION); default to 'v0'
VERSION = os.getenv("VERSION") or os.getenv("APP_VERSION") or "v2"
# Kubernetes typically sets HOSTNAME to the pod name; some setups use POD_NAME via downward API
POD_NAME = os.getenv("POD_NAME") or os.getenv("HOSTNAME") or "unknown"

@app.route("/")
def index():
    """Return basic info: version and pod name"""
    return jsonify({"version": VERSION, "podname": POD_NAME})

@app.route("/version")
def get_version():
    return jsonify({"version": VERSION})

@app.route("/pod")
def get_pod():
    return jsonify({"podname": POD_NAME})

@app.route("/health")
def health():
    return Response("ok", status=200, mimetype="text/plain")

if __name__ == "__main__":
    # Bind to PORT env or default 8080
    port = int(os.getenv("PORT", "8080"))
    app.logger.info(f"Starting simple-responder version={VERSION} pod={POD_NAME} on :{port}")
    app.run(host="0.0.0.0", port=port)

