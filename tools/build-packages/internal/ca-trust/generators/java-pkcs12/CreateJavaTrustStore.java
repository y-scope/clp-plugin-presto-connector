// Creates the Java PKCS#12 store inside the temporary JDK generator container.
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.util.Enumeration;
import java.util.HexFormat;

final class CreateJavaTrustStore {
    private CreateJavaTrustStore() {}

    public static void main(String[] args) throws Exception {
        if (args.length != 4) {
            throw new IllegalArgumentException(
                    "Usage: CreateJavaTrustStore <host-ca> <base-trust-store> <output-pkcs12> <password>");
        }

        Path hostCa = Path.of(args[0]);
        Path baseTrustStore = Path.of(args[1]);
        Path outputTrustStore = Path.of(args[2]);
        char[] password = args[3].toCharArray();

        KeyStore base = KeyStore.getInstance(baseTrustStore.toFile(), password);
        KeyStore trustStore = KeyStore.getInstance("PKCS12");
        trustStore.load(null, password);
        for (Enumeration<String> aliases = base.aliases(); aliases.hasMoreElements(); ) {
            String alias = aliases.nextElement();
            if (base.isCertificateEntry(alias)) {
                trustStore.setCertificateEntry(alias, base.getCertificate(alias));
            }
        }

        CertificateFactory certificateFactory = CertificateFactory.getInstance("X.509");
        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        try (InputStream input = Files.newInputStream(hostCa)) {
            for (Certificate certificate : certificateFactory.generateCertificates(input)) {
                String fingerprint = HexFormat.of().formatHex(sha256.digest(certificate.getEncoded()));
                trustStore.setCertificateEntry("host-ca-" + fingerprint, certificate);
            }
        }

        try (OutputStream output = Files.newOutputStream(outputTrustStore)) {
            trustStore.store(output, password);
        }
    }
}
