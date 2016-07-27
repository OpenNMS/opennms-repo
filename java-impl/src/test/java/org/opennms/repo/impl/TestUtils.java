package org.opennms.repo.impl;

import java.io.IOException;

import org.bouncycastle.openpgp.PGPException;
import org.bouncycastle.openpgp.PGPSecretKey;
import org.opennms.repo.api.GPGInfo;

public abstract class TestUtils {
    private TestUtils() {}

    public static GPGInfo generateGPGInfo() throws IOException, InterruptedException, PGPException {
        final String keyId = "foo@bar.com";
        final String passphrase = "12345";
        final PGPSecretKey key = GPGUtils.generateKey(keyId, passphrase);
        final GPGInfo gpginfo = new GPGInfo(keyId, passphrase, key);
        return gpginfo;
    }
}
