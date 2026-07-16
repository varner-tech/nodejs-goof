# goof-python

A small, intentionally-vulnerable Python companion service for the `nodejs-goof`
demo app. It exists to demonstrate that [Snyk](https://snyk.io/) can detect a
Python project managed with the [uv](https://docs.astral.sh/uv/) package manager
alongside a JavaScript project in the same repository.

## Package manager

This project is managed with **uv**. Dependencies are declared in
`pyproject.toml` and pinned in `uv.lock`.

```bash
# install uv (https://docs.astral.sh/uv/getting-started/installation/)
curl -LsSf https://astral.sh/uv/install.sh | sh

# resolve + install into a local virtual environment
uv sync

# run the service
uv run python -m goof_python.app
```

## Note

The pinned dependency versions here are deliberately old and contain known
vulnerabilities so that Snyk has something to report. Do not use this as a
starting point for real projects.
