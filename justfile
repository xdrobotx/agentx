set shell := ["bash", "-cu"]

default:
    @just --list

update:
    git submodule update --init --recursive

update-latest:
    git submodule update --remote --merge

build:
    @if [ "$(uname -s)" = "Linux" ]; then \
        ./scripts/build-llamacpp.sh ; \
    else \
        powershell -ExecutionPolicy Bypass -File ./scripts/build-llamacpp.ps1 ; \
    fi

clean:
    rm -rf llama.cpp/build

rebuild:
    just clean
    just build

status:
    git submodule status
