#!/usr/bin/env python3
"""
Add NVIDIA runtime configuration to containers.conf.
"""
import sys

def add_nvidia_runtime(path):
    try:
        with open(path, "r") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Warning: {path} not found, creating it")
        content = ""
    
    if "nvidia" in content:
        print(f"NVIDIA runtime already configured in {path}")
        return False
    
    runtime_config = """
[[engine.runtimes]]
name = "nvidia"
path = "/usr/bin/nvidia-container-runtime"
"""
    
    with open(path, "a") as f:
        f.write(runtime_config)
    
    print(f"Added NVIDIA runtime config to {path}")
    return True

def main():
    paths = [
        "/etc/containers/containers.conf",
    ]
    
    for path in paths:
        add_nvidia_runtime(path)
    
    print("NVIDIA runtime configuration complete.")

if __name__ == "__main__":
    main()
