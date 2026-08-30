#!/usr/bin/env python3
"""
Fix Podman CDI configuration in containers.conf.
Fedora ships CDI spec dirs commented out by default.
"""
import re
import sys

def fix_containers_conf(path):
    with open(path, "r") as f:
        lines = f.readlines()
    
    modified = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "#cdi_spec_dirs":
            lines[i] = line.replace("#cdi_spec_dirs", "cdi_spec_dirs")
            modified = True
        elif stripped == '#  "/etc/cdi"':
            lines[i] = line.replace('#  "/etc/cdi"', '  "/etc/cdi"')
            modified = True
        elif stripped == '#  "/var/run/cdi"':
            lines[i] = line.replace('#  "/var/run/cdi"', '  "/var/run/cdi"')
            modified = True
    
    if modified:
        with open(f"{path}.tmp", "w") as f:
            f.writelines(lines)
        print(f"Fixed: {path}")
        return True
    else:
        print(f"No changes needed: {path}")
        return False

def main():
    paths = [
        "/usr/share/containers/containers.conf",
    ]
    
    for path in paths:
        try:
            fix_containers_conf(path)
        except FileNotFoundError:
            print(f"Warning: {path} not found, skipping")
    
    print("CDI configuration fix complete.")

if __name__ == "__main__":
    main()
