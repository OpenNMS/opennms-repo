package org.opennms.repo.api;

import java.io.BufferedOutputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Iterator;

import org.bouncycastle.openpgp.PGPException;
import org.bouncycastle.openpgp.PGPPrivateKey;
import org.bouncycastle.openpgp.PGPPublicKey;
import org.bouncycastle.openpgp.PGPPublicKeyRing;
import org.bouncycastle.openpgp.PGPPublicKeyRingCollection;
import org.bouncycastle.openpgp.PGPSecretKey;
import org.bouncycastle.openpgp.PGPSecretKeyRing;
import org.bouncycastle.openpgp.PGPSecretKeyRingCollection;
import org.bouncycastle.openpgp.operator.PBESecretKeyDecryptor;
import org.bouncycastle.openpgp.operator.bc.BcPBESecretKeyDecryptorBuilder;
import org.bouncycastle.openpgp.operator.bc.BcPGPDigestCalculatorProvider;
import org.bouncycastle.openpgp.operator.jcajce.JcaKeyFingerprintCalculator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class GPGInfo {
	private static final Logger LOG = LoggerFactory.getLogger(GPGInfo.class);

	private final String m_keyId;
	private final String m_passphrase;
	private final PGPSecretKey m_secretKey;
	private final PGPPrivateKey m_privateKey;
	private final PGPPublicKey m_publicKey;
	private final PGPPublicKeyRingCollection m_publicKeyRing;
	private final PGPSecretKeyRingCollection m_privateKeyRing;

	public GPGInfo(final String keyId, final String passphrase, final PGPSecretKey secretKey)
			throws IOException, PGPException {
		m_keyId = keyId;
		m_passphrase = passphrase;
		m_secretKey = secretKey;
		m_publicKey = secretKey.getPublicKey();
		m_privateKey = extractPrivateKey(secretKey, passphrase);
		m_publicKeyRing = createKeyring(m_publicKey);
		m_privateKeyRing = null;
	}

	public GPGInfo(final String keyId, final PGPPublicKey publicKey) throws IOException, PGPException {
		m_keyId = keyId;
		m_publicKey = publicKey;
		m_passphrase = null;
		m_secretKey = null;
		m_privateKey = null;
		m_publicKeyRing = createKeyring(publicKey);
		m_privateKeyRing = null;
	}

	public GPGInfo(final String keyId, final String passphrase, final PGPPublicKeyRing publicRing,
			final PGPSecretKeyRing secretRing) {
		try {
			m_keyId = keyId;
			m_passphrase = passphrase;
			m_publicKeyRing = new PGPPublicKeyRingCollection(Arrays.asList(publicRing));
			m_privateKeyRing = new PGPSecretKeyRingCollection(Arrays.asList(secretRing));
			m_publicKey = findPublicKey(publicRing, keyId); // TODO
			m_secretKey = findSecretKey(secretRing, keyId); // TODO
			m_privateKey = extractPrivateKey(m_secretKey, m_passphrase);
		} catch (final PGPException | IOException e) {
			throw new RepositoryException(e);
		}
	}

	private PGPPublicKey findPublicKey(final PGPPublicKeyRing ring, final String keyId) {
		LOG.debug("findPublicKey: {}", keyId);
		final Iterator<PGPPublicKey> keyIter = ring.getPublicKeys();
		while (keyIter.hasNext()) {
			final PGPPublicKey key = keyIter.next();
			LOG.debug("checking key: {}", key);
			@SuppressWarnings("unchecked")
			final Iterator<Object> idIter = key.getUserIDs();
			while (idIter.hasNext()) {
				final String id = idIter.next().toString();
				if (id.toLowerCase().contains(keyId)) {
					LOG.debug("found public key: {}", key);
					return key;
				}
			}
		}
		LOG.warn("Unable to locate key {} in public keyring.", keyId);
		return null;
	}

	private PGPSecretKey findSecretKey(final PGPSecretKeyRing ring, final String keyId) {
		LOG.debug("findSecretKey: {}", keyId);
		final Iterator<PGPSecretKey> keyIter = ring.getSecretKeys();
		while (keyIter.hasNext()) {
			final PGPSecretKey key = keyIter.next();
			LOG.debug("checking key: {}", key);
			@SuppressWarnings("unchecked")
			final Iterator<Object> idIter = key.getUserIDs();
			while (idIter.hasNext()) {
				final String id = idIter.next().toString();
				if (id.toLowerCase().contains(keyId)) {
					LOG.debug("found secret key: {}", key);
					return key;
				}
			}
		}
		LOG.warn("Unable to locate key {} in secret keyring.", keyId);
		return null;
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

	public void savePublicKeyring(final Path path) {
		try (final FileOutputStream fos = new FileOutputStream(path.toFile());
				final BufferedOutputStream bos = new BufferedOutputStream(fos);) {
			m_publicKeyRing.encode(bos);
		} catch (final Exception e) {
			throw new RepositoryException("Failed to save public keyring to " + path, e);
		}
	}

	public void savePrivateKeyring(final Path path) {
		try (final FileOutputStream fos = new FileOutputStream(path.toFile());
				final BufferedOutputStream bos = new BufferedOutputStream(fos);) {
			m_privateKeyRing.encode(bos);
		} catch (final Exception e) {
			throw new RepositoryException("Failed to save private keyring to " + path, e);
		}
	}

	private static PGPPrivateKey extractPrivateKey(final PGPSecretKey secretKey, final String passphrase)
			throws PGPException {
		if (secretKey == null) {
			return null;
		}
		// final PBESecretKeyDecryptor decryptor = new
		// JcePBESecretKeyDecryptorBuilder().setProvider("BC").build(passphrase.toCharArray());
		final PBESecretKeyDecryptor decryptor = new BcPBESecretKeyDecryptorBuilder(new BcPGPDigestCalculatorProvider())
				.build(passphrase.toCharArray());
		return secretKey.extractPrivateKey(decryptor);
	}

	private PGPPublicKeyRingCollection createKeyring(final PGPPublicKey publicKey) throws IOException, PGPException {
		final PGPPublicKeyRing kr = new PGPPublicKeyRing(publicKey.getPublicKeyPacket().getEncoded(),
				new JcaKeyFingerprintCalculator());
		return new PGPPublicKeyRingCollection(Arrays.asList(kr));
	}
}
