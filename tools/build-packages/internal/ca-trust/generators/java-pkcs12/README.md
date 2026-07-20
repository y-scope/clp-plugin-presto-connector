# Java PKCS#12 generator

A `generators/` backend that produces a Java PKCS#12 trust store from a staged
PEM CA bundle. Used by `host.sh::stage_java_pkcs12`; also runnable directly.

## Usage

```bash
./tools/build-packages/internal/ca-trust/generators/java-pkcs12/generate.sh \
    <host-ca-bundle.pem> <truststore.p12>
```

It needs a JDK: it reads `JAVA_HOME`, falling back to `java` on `PATH`. Given
the inputs, it:

1. Locates the base JDK trust store (`jssecacerts` if present, else `cacerts`).
2. Copies its trusted certificates into a new PKCS#12 store.
3. Imports the staged PEM bundle using SHA-256-based aliases.
4. Writes the result to the output path (store password `changeit`, an
   integrity password for public certificates, not a secret).

The output store is then supplied to Maven via
`-Djavax.net.ssl.trustStore=<path> -Djavax.net.ssl.trustStoreType=PKCS12
-Djavax.net.ssl.trustStorePassword=changeit`, avoiding edits to the JDK's
installed `cacerts`. `container.sh` appends these to `MAVEN_OPTS`
automatically.

## Notes

PKCS#12 is a standard format, not JDK-specific. The generator runs in a pinned
Temurin JDK 17 image by default to keep the generator environment and base
certificate set stable; set `CA_TRUST_JAVA_PKCS12_GENERATOR_IMAGE` to override.
The caller mounts the output read-only for the build and removes it afterward
— it never enters the image, caches, packages, or layers.

## Files

- `generate.sh` — validates inputs, locates the JDK trust store, runs the converter.
- `CreateJavaTrustStore.java` — copies the base certificates and imports the PEM bundle.
