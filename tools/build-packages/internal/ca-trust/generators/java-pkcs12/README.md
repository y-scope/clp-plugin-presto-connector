# Java PKCS#12 generator

This backend creates a Java PKCS#12 trust store from a staged PEM CA bundle.

## Why it is needed

Java's TLS implementation does not use environment variables such as `SSL_CERT_FILE`, `CURL_CA_BUNDLE`, or `REQUESTS_CA_BUNDLE`. It normally reads the JDK trust store, or a custom store selected with Java system properties. The packaging flow supplies the generated store to Maven with:

```text
-Djavax.net.ssl.trustStore=/path/to/truststore.p12
-Djavax.net.ssl.trustStoreType=PKCS12
-Djavax.net.ssl.trustStorePassword=changeit
```

This avoids modifying the JDK's installed `cacerts` file.

## What it does

Given `generate.sh <host-ca-bundle.pem> <truststore.p12>`, the backend:

1. Detects the base JDK trust store (`jssecacerts` if present, otherwise `cacerts`).
2. Copies its trusted certificates into a new PKCS#12 store.
3. Adds certificates from the staged PEM bundle using SHA-256-based aliases.
4. Writes the result to the requested path.

PKCS#12 is a standard format rather than a JDK-specific format. The generator currently uses a pinned Temurin JDK 17 image to keep the generator environment and base certificate set stable. Set `CA_TRUST_JAVA_PKCS12_GENERATOR_IMAGE` to use a different generator image.

The caller mounts the generated file read-only for the packaging build and removes it afterward. It is not copied into the dependency image, caches, packages, or image layers.

## Files

- `generate.sh` validates the inputs, locates the JDK trust store, and invokes the converter.
- `CreateJavaTrustStore.java` copies the base certificates and imports the staged PEM certificates.
