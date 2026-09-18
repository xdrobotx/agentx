#!/usr/bin/env python3
# =============================================================================
# Container Config Parser
#
# Reads a JSON model config and a param-map, validates inputs, and outputs
# a single line of llama-server CLI arguments.
#
# Usage:
#   python3 parser.py <config.json>
#
# Output (stdout):
#   --flag1 value1 --flag2 value2 ...
#
# Errors (stderr):
#   Validation errors with line numbers
# =============================================================================

import json
import sys
import os
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
PARAM_MAP_FILE = SCRIPT_DIR / "param-map.json"


def load_param_map():
    """Load the parameter mapping file."""
    with open(PARAM_MAP_FILE, "r") as f:
        return json.load(f)


def load_config(path: str) -> dict:
    """Load and validate the model config file."""
    config_path = Path(path)
    if not config_path.is_file():
        print(f"Error: Config file not found: {path}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(config_path, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {path}: {e}", file=sys.stderr)
        sys.exit(1)


def resolve_wsl2_path(path_str: str) -> str:
    """
    Resolve a path for container mounting.
    If the path starts with /mnt/, it's already WSL2-compatible.
    Expands environment variables (e.g., $LLAMA_MODELS_PATH).
    Returns the path as-is if it contains unresolved env vars.
    """
    if not path_str:
        return path_str
    # Expand environment variables
    import os
    expanded = os.path.expandvars(path_str)
    if expanded != path_str:
        path_str = expanded
    if path_str.startswith("/mnt/"):
        return path_str
    if path_str.startswith("/"):
        return path_str
    # Relative path — resolve relative to current directory
    return str(Path(path_str).resolve())


def validate_config(config: dict, param_map: dict) -> list:
    """
    Validate the config against the param map.
    Returns a list of (key, error_message) tuples.
    """
    errors = []

    # Check required fields
    if "model" not in config:
        errors.append(("model", "Required field 'model' (model subdirectory) is missing"))
    elif "model_path" not in config:
        errors.append(("model_path", "Required field 'model_path' (full GGUF path) is missing"))

    # Check for unknown keys (warn, don't error)
    known_keys = set(param_map.keys())
    for key in config:
        if key not in known_keys and key not in ("model", "model_path", "cuda_version"):
            print(f"Warning: Unknown config key '{key}' (ignored)", file=sys.stderr)

    return errors


def generate_cli_args(config: dict, param_map: dict) -> str:
    """Generate a single-line string of llama-server CLI arguments."""
    args = []

    # 1. Handle Model Path correctly based on basename
    model_path = resolve_wsl2_path(config.get("model_path", ""))
    if model_path:
        basename = os.path.basename(model_path)
        args.append(f"--model /models/{basename}")

    # 2. Handle Multimodal (mmproj)
    mmproj = config.get("mmproj")
    if mmproj:
        expanded = os.path.expandvars(mmproj)
        basename = os.path.basename(expanded)
        args.append(f"--mmproj /models/{basename}")

    # 3. Always enforce host and port so llama-server binds to 0.0.0.0
    host = config.get("host", "0.0.0.0")
    port = config.get("port", 9696)
    args.append(f"--host {host}")
    args.append(f"--port {port}")

    # 4. Map remaining config keys
    for key, value in config.items():
        if key in ("model", "model_path", "cuda_version", "mmproj", "host", "port"):
            continue  # Already handled
        if key.startswith("_"):
            continue  # Skip comments/internal keys

        if key not in param_map or not isinstance(param_map[key], dict):
            continue

        mapping = param_map[key]
        flag = mapping["flag"]
        value_type = mapping["type"]

        # Convert type
        if value_type == "int":
            value = int(value)
        elif value_type == "float":
            value = float(value)
        elif value_type == "bool":
            if isinstance(value, str):
                value = value.lower() in ("true", "1", "yes", "on")
            elif isinstance(value, int):
                value = bool(value)

        # Boolean flags
        if value_type == "bool":
            if value:
                args.append(flag)
            continue

        # Handle quoted strings
        if flag == "--chat-template-kwargs":
            args.append(f"{flag} '{value}'")
            continue

        args.append(f"{flag} {value}")

    return " ".join(args)


def main():
    if len(sys.argv) < 2:
        print("Usage: parser.py <config.json>", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]

    # Load files
    param_map = load_param_map()
    config = load_config(config_path)

    # Validate
    errors = validate_config(config, param_map)
    if errors:
        for key, err in errors:
            print(f"Error in config: {err}", file=sys.stderr)
        sys.exit(1)

    # Generate CLI args
    cli_args = generate_cli_args(config, param_map)

    # Output to stdout (single line)
    print(cli_args)


if __name__ == "__main__":
    main()
