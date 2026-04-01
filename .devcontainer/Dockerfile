FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies for Sail and its C backend
RUN apt-get update && apt-get install -y \
    opam gcc make cmake pkg-config \
    libgmp-dev zlib1g-dev z3 \
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

WORKDIR /workspace
