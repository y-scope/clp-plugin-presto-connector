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

TRUST_DIR="$(mktemp -d)"
trap 'rm -rf "${TRUST_DIR}"' EXIT
stage_host_ca_bundle "${TRUST_DIR}"      # -> ${TRUST_DIR}/ca-bundle.pem (0444)
stage_java_pkcs12 "${TRUST_DIR}"         # -> ${TRUST_DIR}/truststore.p12 (0444)

docker run --rm \
    --mount "type=bind,src=${TRUST_DIR},dst=${CA_TRUST_CONTAINER_DIR},readonly" \
    --env "CA_TRUST_DIR=${CA_TRUST_CONTAINER_DIR}" \
    --env MAVEN_OPTS \
    <image> bash -c '
        source /repo/tools/build-packages/internal/ca-trust/container.sh
        # ... run the build; curl/git/pip/Maven now use the staged stores
    '
```

Call `stage_host_ca_bundle` for the PEM bundle alone, `stage_java_pkcs12` for
the Java store, or both when the build consumes each (as above).

## Host API (`host.sh`)

| Function | Args | Effect |
|---|---|---|
| `stage_host_ca_bundle` | `<trust-dir>` | Writes `<trust-dir>/${CA_TRUST_BUNDLE_FILENAME}` (`0444`). Uses `SSL_CERT_FILE` when set, else searches common Linux CA-bundle locations; creates an empty file if none is found. |
| `stage_java_pkcs12` | `<trust-dir>` | Writes `<trust-dir>/${CA_TRUST_JAVA_STORE_FILENAME}` merging the JDK defaults with the staged bundle, via a temporary pinned-JDK container (`--network none`, host UID/GID). Run `stage_host_ca_bundle` first. Java need not be installed on the host. |

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