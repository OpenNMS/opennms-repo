package org.opennms.repo.impl;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.io.StringBufferInputStream;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;

import org.apache.commons.io.IOUtils;
import org.bouncycastle.openpgp.PGPPublicKey;
import org.bouncycastle.openpgp.PGPSecretKey;
import org.bouncycastle.openpgp.PGPSignature;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@SuppressWarnings("deprecation")
public class GPGUtilsTest {
    private static final Logger LOG = LoggerFactory.getLogger(GPGUtilsTest.class);

    private static final String KEY_EMAIL = "bob@example.com";
    private static final String KEY_PASSPHRASE = "12345";

    private static final String OPENNMS_PUBKEY_WITH_SIGNATURES = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n" +
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
            "iGYEExECACYFAk8cWjoCGwMFCQWjmoAGCwkIBwMCBBUCCAMEFgIDAQIeAQIXgAAK\n" +
            "CRBXgB9vW579Q5FNAJwOfC/jnud3i/pfTxjvHiEQA2QpjgCfe3ydUPAbPdV0m3jx\n" +
            "zfwq5+3WQg2IZgQTEQIAJgIbAwYLCQgHAwIEFQIIAwQWAgMBAh4BAheABQJUwANF\n" +
            "BQkPCaqLAAoJEFeAH29bnv1D9RwAn20L7xnR4tSygZqqKkxcC5sAFrMpAJ9DtClb\n" +
            "7O1zrHthZ2UTZIPpom1KAIhgBBMRAgAgAhsDBgsJCAcDAgQVAggDBBYCAwECHgEC\n" +
            "F4AFAlTGpjAACgkQV4Afb1ue/UPpbQCfcuVbOndjUyNpgDF5JssmuK6vd1QAn09b\n" +
            "X/1mcaESjKICe0BRV7N+0bFvuQENBE8cWjoQBACzbdh9E3rBWncNoNCmp+i+sQI4\n" +
            "69+6m/vNVxUYpP79Vq4wC1Mn+JVtqUnY907Inux/gzoeedALDRNQR//mbTKzOrjA\n" +
            "iG98BGP7qd6kJJcXXJK1OmPxPOVvHbh2IMg1N0sGSsYHosOgEPKik/Mg8u7Angxz\n" +
            "5WjJd6VgYPFLv/pgXwADBQP+P/mppqcQsSsUXEowEOHp4spVFBkZT0f4v7QAa/39\n" +
            "+i0NfhoFxVG1G4rtiAFnW6ShYWkbexhKVoP7i7MZdBj8vlvP94QGtM9BxuBqIIzy\n" +
            "2qIZNJ1/ISd1bHUq5D3XetV5z4WEtYmlkVs1HLpdMXrq40D5CuKWGjgmXq0CNeUE\n" +
            "3bmITwQYEQIADwUCTxxaOgIbDAUJBaOagAAKCRBXgB9vW579QygTAJ9uOybiQ5w3\n" +
            "7HhNxEn+bjAAaOB4wACdH62fHMTduH4Cm+zYIoKj/hWb0aWISQQYEQIACQIbDAUC\n" +
            "VMamGwAKCRBXgB9vW579Q/4vAJwLgBtbY9eBETaFXFeEpBSMeqoDCwCeOUqvKV5U\n" +
            "OnRUAWJ91FGZtqVJUWg=\n" +
            "=/H8o\n" +
            "-----END PGP PUBLIC KEY BLOCK-----\n";

    private static final String OPENNMS_PUBKEY_WITHOUT_SIGNATURES = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n" + 
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
    @SuppressWarnings("rawtypes")
    public void testExportPublicKey() throws Exception {
        try (final StringBufferInputStream is = new StringBufferInputStream(OPENNMS_PUBKEY_WITH_SIGNATURES)) {
            final PGPPublicKey key = PGPExampleUtil.readPublicKey(is);

            LOG.debug("creationtime: {}", key.getCreationTime());
            LOG.debug("bitstrength: {}", key.getBitStrength());
            LOG.debug("keyid: {}", key.getKeyID());
            LOG.debug("publickey: {}", key.getPublicKeyPacket());

            final Iterator userids = key.getUserIDs();
            while (userids.hasNext()) {
                LOG.debug("userid: {}", userids.next());
            }

            final Iterator userattrs = key.getUserAttributes();
            while (userattrs.hasNext()) {
                LOG.debug("attr: {}", userattrs.next());
            }

            final List<PGPSignature> sigs = new ArrayList<>();
            final Iterator signatures = key.getKeySignatures();
            while (signatures.hasNext()) {
                final PGPSignature sig = (PGPSignature) signatures.next();
                sigs.add(sig);
                LOG.debug("signature: {}", sig);
            }
            
            assertEquals(2, sigs.size());
        }
        try (final StringBufferInputStream is = new StringBufferInputStream(OPENNMS_PUBKEY_WITHOUT_SIGNATURES)) {
            final PGPPublicKey key = PGPExampleUtil.readPublicKey(is);
            
            final List<PGPSignature> sigs = new ArrayList<>();
            final Iterator signatures = key.getKeySignatures();
            while (signatures.hasNext()) {
                final PGPSignature sig = (PGPSignature) signatures.next();
                sigs.add(sig);
                LOG.debug("signature: {}", sig);
            }
            
            assertEquals(2, sigs.size());

        }
    }
}
