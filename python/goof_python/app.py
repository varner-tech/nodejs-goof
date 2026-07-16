"""A tiny Flask service used to demonstrate Snyk detection of a uv-managed
Python project living alongside the Node.js goof app.

This is demo code for a deliberately-vulnerable sample repository.
"""

import yaml
import requests
from flask import Flask, request, jsonify

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/parse", methods=["POST"])
def parse_config():
    raw = request.get_data(as_text=True)
    parsed = yaml.load(raw)
    return jsonify(parsed=parsed)


@app.route("/fetch")
def fetch():
    url = request.args.get("url", "https://snyk.io")
    resp = requests.get(url)
    return jsonify(status_code=resp.status_code)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
