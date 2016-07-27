package org.opennms.repo.impl;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.InputStream;
import java.io.StringBufferInputStream;
import java.nio.charset.Charset;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Collection;
import java.util.Collections;
import java.util.List;

import org.apache.commons.io.IOUtils;
import org.bouncycastle.openpgp.PGPPublicKeyRingCollection;
import org.bouncycastle.openpgp.PGPSecretKey;
import org.bouncycastle.openpgp.PGPUtil;
import org.bouncycastle.openpgp.operator.jcajce.JcaKeyFingerprintCalculator;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@SuppressWarnings("deprecation")
public class GPGUtilsTest {
    @SuppressWarnings("unused")
    private static final Logger LOG = LoggerFactory.getLogger(GPGUtilsTest.class);

    private static final String KEY_EMAIL = "bob@example.com";
    private static final String KEY_PASSPHRASE = "12345";

    private static final String OPENNMS_PUBKEY = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n" + 
            "Version: GnuPG v1\n" + 
            "\n" + 
            "mQGiBE8cWjoRBACVT11pxtPwvUeP3EbCG56IRnkUyEhdf0Daj9wGeFbY9I6nRr31\n" + 
            "U/YqrDDMKyGBYCBRJ3FxrzNfSfUX8WVD4FtxhAmqyC3+nTn9PqdSLbVePuuFDyba\n" + 
            "Q/AGKclRAPSCbqR2YjZQVy3ITxiUQ8SpRE37cvSlgLOTsYpbwXpSTy02MwCgi74K\n" + 
            "jOxF3KP2xECe7GSo9Xmul30D/jDbbmmGQ3OcrNi1inVcOk7OFyObtX5pIR+oMvBV\n" + 
            "6MBlexGLeNgKGjbptURnX8OqXIwVMA6dunbKOgj+5HACOkN00ead9nJ8njrvwlEL\n" + 
            "3WD9xT4c9CejiaykKoNn752LQFRopX1/eLMmKu5iY55GRItEeIIounYdljHaN9Ms\n" + 
            "OzJ1A/9kPJilfG8/9nMK2U2cszZu/z13xchBtz+aLs1fvPF7ZT3zS7Fqzl1FLRZn\n" + 
            "5fp5W6ZCao1ZLJtykAgXmdnNkRucem5kzFqCA3+gtG++GRs7K/4G+BhbjQ8ydHwc\n" + 
            "aklq8dnYXiOC6ffAWNrWJ20ULkWayjImm3RIAXqupi7o26J/EbQ5T3Blbk5NUyBT\n" + 
            "aWduaW5nIEtleSAyMDEyICgxMDI0LWJpdCkgPG9wZW5ubXNAb3Blbm5tcy5vcmc+\n" + 
            "iGAEExECACACGwMGCwkIBwMCBBUCCAMEFgIDAQIeAQIXgAUCVMamMAAKCRBXgB9v\n" + 
            "W579Q+ltAJ9y5Vs6d2NTI2mAMXkmyya4rq93VACfT1tf/WZxoRKMogJ7QFFXs37R\n" + 
            "sW+5AQ0ETxxaOhAEALNt2H0TesFadw2g0Kan6L6xAjjr37qb+81XFRik/v1WrjAL\n" + 
            "Uyf4lW2pSdj3Tsie7H+DOh550AsNE1BH/+ZtMrM6uMCIb3wEY/up3qQklxdckrU6\n" + 
            "Y/E85W8duHYgyDU3SwZKxgeiw6AQ8qKT8yDy7sCeDHPlaMl3pWBg8Uu/+mBfAAMF\n" + 
            "A/4/+ammpxCxKxRcSjAQ4eniylUUGRlPR/i/tABr/f36LQ1+GgXFUbUbiu2IAWdb\n" + 
            "pKFhaRt7GEpWg/uLsxl0GPy+W8/3hAa0z0HG4GogjPLaohk0nX8hJ3VsdSrkPdd6\n" + 
            "1XnPhYS1iaWRWzUcul0xeurjQPkK4pYaOCZerQI15QTduYhPBBgRAgAPBQJPHFo6\n" + 
            "AhsMBQkFo5qAAAoJEFeAH29bnv1DKBMAn247JuJDnDfseE3ESf5uMABo4HjAAJ0f\n" + 
            "rZ8cxN24fgKb7NgigqP+FZvRpYhJBBgRAgAJAhsMBQJUxqYbAAoJEFeAH29bnv1D\n" + 
            "/i8AnAuAG1tj14ERNoVcV4SkFIx6qgMLAJ45Sq8pXlQ6dFQBYn3UUZm2pUlRaA==\n" + 
            "=EsqR\n" + 
            "-----END PGP PUBLIC KEY BLOCK-----\n";

    @Test
    public void testGenerateKey() throws Exception {
        final PGPSecretKey key = GPGUtils.generateKey(KEY_EMAIL, KEY_PASSPHRASE);
        assertNotNull(key);
        assertNotNull(key.getPublicKey());
        assertTrue(key.getPublicKey().getUserIDs().hasNext());
        assertEquals(KEY_EMAIL, key.getPublicKey().getUserIDs().next().toString());
    }

    @Test
    public void testSignFile() throws Exception {
        final PGPSecretKey key = GPGUtils.generateKey(KEY_EMAIL, KEY_PASSPHRASE);
        final File input = File.createTempFile("encryptme", ".txt");
        input.deleteOnExit();
        try (FileWriter fw = new FileWriter(input)) {
            fw.write("blah\n");
        }

        final File output = new File(input.toString() + ".asc");
        output.deleteOnExit();
        GPGUtils.detach_sign(input.toPath(), output.toPath(), new GPGInfo(KEY_EMAIL, KEY_PASSPHRASE, key), false);

        assertTrue(output.exists());
        assertTrue(output.length() > 0);

        Collection<String> encrypted = Collections.emptyList();
        try (final InputStream is = new FileInputStream(output)) {
            encrypted = IOUtils.readLines(is, Charset.defaultCharset());
        }

        //System.out.println(String.join("\n", encrypted));
        assertTrue(encrypted.iterator().next().equals("-----BEGIN PGP SIGNATURE-----"));
    }

    @Test
    public void testExportPublicKey() throws Exception {
        final Path keyfile = Paths.get("target/GPGUtilsTest.testExportPublicKey.asc");
        try (final StringBufferInputStream is = new StringBufferInputStream(OPENNMS_PUBKEY)) {
            final PGPPublicKeyRingCollection pgpPub = new PGPPublicKeyRingCollection(PGPUtil.getDecoderStream(is), new JcaKeyFingerprintCalculator());
            GPGUtils.exportKeyRing(keyfile, pgpPub);
        }
        assertTrue(keyfile.toFile().exists());
        final List<String> lines = IOUtils.readLines(new FileReader(keyfile.toFile()));
        final String key = String.join("\n", lines);

        // we do "contains" rather than equals because GPG adds an extra packet to the end
        assertTrue(key.contains("BEGIN PGP PUBLIC KEY BLOCK"));
        assertTrue(key.contains("mQGiBE8cWjoRBACVT11pxtPwvUeP3EbCG56IRnkUyEhdf0Daj9wGeFbY9I6nRr31"));
        assertTrue(key.contains("/i8AnAuAG1tj14ERNoVcV4SkFIx6qgMLAJ45Sq8pXlQ6dFQBYn3UUZm2pUlRaA=="));
    }
}
