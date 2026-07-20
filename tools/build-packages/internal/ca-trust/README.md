# CA trust

A reusable library for propagating the host's trusted certificates into a
containerized build behind a corporate TLS gateway, without installing them in
an image or persisting them in layers, caches, or artifacts.

## Quick start

On the host, stage the trust stores and bind-mount them into the build
container; in the container, point `CA_TRUST_DIR` at the mount and source
`container.sh`.

```bash
# Host side
source tools/build-packages/internal/ca-trust/host.sh

trust_dir="$(mktemp -d)"
trap 'rm -rf "${trust_dir}"' EXIT
stage_container_ca_trust "${trust_dir}"          # writes ca-bundle.pem + truststore.p12 (mode 0444)

docker run --rm \
    --mount "type=bind,src=${trust_dir},dst=${CA_TRUST_CONTAINER_DIR},readonly" \
    --env "CA_TRUST_DIR=${CA_TRUST_CONTAINER_DIR}" \
    --env MAVEN_OPTS \
    <image> bash -c '
        source /repo/tools/build-packages/internal/ca-trust/container.sh
        # ... run the build; curl/git/pip/Maven now use the staged stores
    '
```

`stage_container_ca_trust` is the one-call entry point. To stage the formats
separately or under non-default names, call the lower-level functions directly:

```bash
stage_host_ca_bundle ./ca-bundle.pem
stage_java_pkcs12 ./ca-bundle.pem ./truststore.p12
```

## Host API (`host.sh`)

| Function | Args | Effect |
|---|---|---|
| `stage_container_ca_trust` | `<trust-dir>` | Writes `<trust-dir>/ca-bundle.pem` and `<trust-dir>/truststore.p12` (both `0444`). The one-call entry point. |
| `stage_host_ca_bundle` | `<dest>` | Copies the host CA bundle to `<dest>` (`0444`). Uses `SSL_CERT_FILE` when set, else searches common Linux CA-bundle locations; creates an empty file if none is found. |
| `stage_java_pkcs12` | `<input-bundle> <dest>` | Generates a PKCS#12 trust store merging the JDK defaults with `<input-bundle>`, via a temporary pinned-JDK container (`--network none`, host UID/GID). Java need not be installed on the host. |

Constants: `CA_TRUST_BUNDLE_FILENAME` (`ca-bundle.pem`),
`CA_TRUST_JAVA_STORE_FILENAME` (`truststore.p12`), and
`CA_TRUST_CONTAINER_DIR` (`/run/ca-trust`, the conventional in-container mount
point to bind the staging directory at and pass as `CA_TRUST_DIR`).

Env override: `CA_TRUST_JAVA_PKCS12_GENERATOR_IMAGE` selects a different
generator image for `stage_java_pkcs12`.

## Container API (`container.sh`)

Source it in the container after setting `CA_TRUST_DIR`:

```bash
CA_TRUST_DIR=/trusted
source tools/build-packages/internal/ca-trust/container.sh
```

It defaults `HOST_CA_BUNDLE` and `HOST_CA_JAVA_TRUST_STORE` to the conventional
filenames under `CA_TRUST_DIR` (override either to use different paths). When
the PEM bundle is non-empty it exports `CURL_CA_BUNDLE`, `GIT_SSL_CAINFO`,
`PIP_CERT`, `REQUESTS_CA_BUNDLE`, and `SSL_CERT_FILE`. When a Java trust store
is set it appends `-Djavax.net.ssl.trustStore*` to `MAVEN_OPTS` (preserving any
caller-supplied value). A no-op when `CA_TRUST_DIR` is unset, so CI builds that
don't mount a trust directory are unaffected.

The caller owns and cleans up the staging directory; the scripts never modify
the host or container trust stores, only the staged snapshot.

## Extensibility

Add a backend under `generators/` when a tool needs a trust format the PEM
bundle can't be consumed directly. Keep host discovery and lifecycle in
`host.sh`; keep format-specific conversion in the backend. See
`generators/java-pkcs12/README.md`.