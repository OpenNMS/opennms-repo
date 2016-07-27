package org.opennms.repo.api;

import java.io.IOException;
import java.util.Arrays;

import org.bouncycastle.openpgp.PGPException;
import org.bouncycastle.openpgp.PGPPrivateKey;
import org.bouncycastle.openpgp.PGPPublicKey;
import org.bouncycastle.openpgp.PGPPublicKeyRing;
import org.bouncycastle.openpgp.PGPPublicKeyRingCollection;
import org.bouncycastle.openpgp.PGPSecretKey;
import org.bouncycastle.openpgp.operator.jcajce.JcaKeyFingerprintCalculator;
import org.bouncycastle.openpgp.operator.jcajce.JcePBESecretKeyDecryptorBuilder;

public class GPGInfo {
    private final String m_keyId;
    private final String m_passphrase;
    private final PGPSecretKey m_secretKey;
    private final PGPPrivateKey m_privateKey;
    private final PGPPublicKey m_publicKey;
    private final PGPPublicKeyRingCollection m_publicKeyRing;

    public GPGInfo(final String keyId, final String passphrase, final PGPSecretKey secretKey) throws IOException, PGPException {
        m_keyId = keyId;
        m_passphrase = passphrase;
        m_secretKey = secretKey;
        m_publicKey = secretKey.getPublicKey();
        m_privateKey = extractPrivateKey(secretKey, passphrase);
        m_publicKeyRing = createKeyring(m_publicKey);
    }

    public GPGInfo(final String keyId, final PGPPublicKey publicKey) throws IOException, PGPException {
        m_keyId = keyId;
        m_publicKey = publicKey;
        m_passphrase = null;
        m_secretKey = null;
        m_privateKey = null;
        m_publicKeyRing = createKeyring(publicKey);
    }

    public String getKey() {
        return m_keyId;
    }

    public String getPassphrase() {
        return m_passphrase;
    }

    public PGPSecretKey getSecretKey() {
        return m_secretKey;
    }

    public PGPPrivateKey getPrivateKey() {
        return m_privateKey;
    }

    public PGPPublicKey getPublicKey() {
        return m_publicKey;
    }

    public PGPPublicKeyRingCollection getPublicKeyRing() {
        return m_publicKeyRing;
    }

    private static PGPPrivateKey extractPrivateKey(final PGPSecretKey secretKey, final String passphrase) throws PGPException {
        return secretKey.extractPrivateKey(new JcePBESecretKeyDecryptorBuilder().setProvider("BC").build(passphrase.toCharArray()));
    }

    private PGPPublicKeyRingCollection createKeyring(final PGPPublicKey publicKey) throws IOException, PGPException {
        PGPPublicKeyRing kr = new PGPPublicKeyRing(publicKey.getPublicKeyPacket().getEncoded(), new JcaKeyFingerprintCalculator());
        return new PGPPublicKeyRingCollection(Arrays.asList(kr));
    }
    
}
