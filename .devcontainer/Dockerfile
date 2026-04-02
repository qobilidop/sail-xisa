FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies for Sail and its C backend
RUN apt-get update && apt-get install -y \
    opam gcc make cmake pkg-config \
    libgmp-dev zlib1g-dev z3 \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Initialize opam (OCaml package manager)
# --disable-sandboxing is needed inside Docker (no bwrap available)
RUN opam init --disable-sandboxing --yes --bare

# Create an OCaml 5.1.0 switch (compiler environment)
RUN opam switch create 5.1.0

# Install Sail into this switch
RUN eval $(opam env --switch=5.1.0) && opam install sail --yes

# Make opam binaries available without eval $(opam env)
ENV PATH="/root/.opam/5.1.0/bin:${PATH}"
ENV SAIL_DIR="/root/.opam/5.1.0/share/sail"

# Rust toolchain (for WASM simulator)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . /root/.cargo/env \
    && rustup target add wasm32-unknown-unknown

ENV PATH="/root/.cargo/bin:${PATH}"

# wasm-pack (builds Rust → WASM with JS bindings)
RUN cargo install wasm-pack

# Node.js 22 LTS (for Astro frontend)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
