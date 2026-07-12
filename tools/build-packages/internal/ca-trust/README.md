# CA trust

This directory provides reusable CA-trust support for containerized builds in corporate environments. It makes the host's trusted certificates available to build tools without installing them in an image or persisting them in image layers, caches, or build artifacts.

## Design

Trust preparation and consumption are deliberately separate:

1. `host.sh` discovers the host CA bundle and stages temporary trust files.
2. Format-specific backends under `generators/` produce any additional trust-store formats required by build tools.
3. The caller mounts the staged files read-only into the build container.
4. `container.sh` configures tools in the container to use those files.
5. The caller removes the staging directory when the build finishes.

The scripts do not modify either the host or container trust store. The staged files are snapshots used only for the current build.

## Host API

Source `host.sh`, then stage the formats needed by the container:

```bash
source tools/build-packages/internal/ca-trust/host.sh

stage_host_ca_bundle ./trust/ca-bundle.pem
stage_java_pkcs12 ./trust/ca-bundle.pem ./trust/truststore.p12
```

`stage_host_ca_bundle` uses `SSL_CERT_FILE` when it is set. Otherwise, it searches common Linux CA-bundle locations. `stage_java_pkcs12` runs the Java generator in a temporary container, so Java does not need to be installed on the host.

## Container API

After mounting the staging directory, set its container path and source `container.sh`:

```bash
CA_TRUST_DIR=/trusted
source tools/build-packages/internal/ca-trust/container.sh
```

The directory must contain `ca-bundle.pem` and `truststore.p12`. Callers may instead set `HOST_CA_BUNDLE` and `HOST_CA_JAVA_TRUST_STORE` to use different paths. For the PEM bundle, the script exports the standard environment variables used by curl, Git, pip, Python Requests, and OpenSSL-based clients. For the PKCS#12 store, it appends Java trust-store properties to `MAVEN_OPTS`.

## Extensibility

Add a backend under `generators/` when a tool requires a trust format that cannot consume the staged PEM bundle directly. Keep host discovery and lifecycle management in `host.sh`, and keep format-specific conversion in the backend. See `generators/java-pkcs12/README.md` for the current implementation.
