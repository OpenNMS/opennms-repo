package org.opennms.repo.impl;

import java.io.BufferedInputStream;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.IOException;
import java.lang.reflect.Constructor;
import java.math.BigInteger;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.SecureRandom;
import java.security.Security;
import java.util.ArrayList;
import java.util.Date;
import java.util.Iterator;
import java.util.List;

import org.apache.commons.io.FileUtils;
import org.bouncycastle.bcpg.ArmoredOutputStream;
import org.bouncycastle.bcpg.BCPGOutputStream;
import org.bouncycastle.bcpg.HashAlgorithmTags;
import org.bouncycastle.bcpg.SymmetricKeyAlgorithmTags;
import org.bouncycastle.bcpg.sig.Features;
import org.bouncycastle.bcpg.sig.KeyFlags;
import org.bouncycastle.crypto.generators.RSAKeyPairGenerator;
import org.bouncycastle.crypto.params.RSAKeyGenerationParameters;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.openpgp.PGPEncryptedData;
import org.bouncycastle.openpgp.PGPException;
import org.bouncycastle.openpgp.PGPKeyPair;
import org.bouncycastle.openpgp.PGPKeyRingGenerator;
import org.bouncycastle.openpgp.PGPPrivateKey;
import org.bouncycastle.openpgp.PGPPublicKey;
import org.bouncycastle.openpgp.PGPPublicKeyRing;
import org.bouncycastle.openpgp.PGPPublicKeyRingCollection;
import org.bouncycastle.openpgp.PGPSecretKey;
import org.bouncycastle.openpgp.PGPSecretKeyRing;
import org.bouncycastle.openpgp.PGPSecretKeyRingCollection;
import org.bouncycastle.openpgp.PGPSignature;
import org.bouncycastle.openpgp.PGPSignatureGenerator;
import org.bouncycastle.openpgp.PGPSignatureSubpacketGenerator;
import org.bouncycastle.openpgp.PGPUtil;
import org.bouncycastle.openpgp.operator.PBESecretKeyEncryptor;
import org.bouncycastle.openpgp.operator.PGPDigestCalculator;
import org.bouncycastle.openpgp.operator.bc.BcPBESecretKeyEncryptorBuilder;
import org.bouncycastle.openpgp.operator.bc.BcPGPContentSignerBuilder;
import org.bouncycastle.openpgp.operator.bc.BcPGPDigestCalculatorProvider;
import org.bouncycastle.openpgp.operator.bc.BcPGPKeyPair;
import org.bouncycastle.openpgp.operator.jcajce.JcaKeyFingerprintCalculator;
import org.bouncycastle.openpgp.operator.jcajce.JcaPGPContentSignerBuilder;
import org.bouncycastle.openpgp.operator.jcajce.JcaPGPDigestCalculatorProviderBuilder;
import org.bouncycastle.openpgp.operator.jcajce.JcaPGPKeyPair;
import org.bouncycastle.openpgp.operator.jcajce.JcePBESecretKeyEncryptorBuilder;
import org.bouncycastle.util.io.pem.PemObject;
import org.bouncycastle.util.io.pem.PemWriter;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.Util;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class GPGUtils {
	private static final Logger LOG = LoggerFactory.getLogger(GPGUtils.class);
	static {
		Security.addProvider(new BouncyCastleProvider());
	}

	private GPGUtils() {
	}

	// from: https://bouncycastle-pgp-cookbook.blogspot.com/
	//
	// Note: s2kcount is a number between 0 and 0xff that controls the
	// number of times to iterate the password hash before use. More
	// iterations are useful against offline attacks, as it takes more
	// time to check each password. The actual number of iterations is
	// rather complex, and also depends on the hash function in use.
	// Refer to Section 3.7.1.3 in rfc4880.txt. Bigger numbers give
	// you more iterations. As a rough rule of thumb, when using
	// SHA256 as the hashing function, 0x10 gives you about 64
	// iterations, 0x20 about 128, 0x30 about 256 and so on till 0xf0,
	// or about 1 million iterations. The maximum you can go to is
	// 0xff, or about 2 million iterations. I'll use 0xc0 as a
	// default -- about 130,000 iterations.

	public final static PGPKeyRingGenerator generateKeyRingGenerator(final String id, final String pass,
			final int s2kcount) throws Exception {
		// This object generates individual key-pairs.
		RSAKeyPairGenerator kpg = new RSAKeyPairGenerator();

		// Boilerplate RSA parameters, no need to change anything
		// except for the RSA key-size (2048). You can use whatever
		// key-size makes sense for you -- 4096, etc.
		kpg.init(new RSAKeyGenerationParameters(BigInteger.valueOf(0x10001), new SecureRandom(), 2048, 12));

		// First create the master (signing) key with the generator.
		PGPKeyPair rsakp_sign = new BcPGPKeyPair(PGPPublicKey.RSA_SIGN, kpg.generateKeyPair(), new Date());
		// Then an encryption subkey.
		PGPKeyPair rsakp_enc = new BcPGPKeyPair(PGPPublicKey.RSA_ENCRYPT, kpg.generateKeyPair(), new Date());

		// Add a self-signature on the id
		PGPSignatureSubpacketGenerator signhashgen = new PGPSignatureSubpacketGenerator();

		// Add signed metadata on the signature.
		// 1) Declare its purpose
		signhashgen.setKeyFlags(false, KeyFlags.SIGN_DATA | KeyFlags.CERTIFY_OTHER);
		// 2) Set preferences for secondary crypto algorithms to use
		// when sending messages to this key.
		signhashgen.setPreferredSymmetricAlgorithms(false, new int[] { SymmetricKeyAlgorithmTags.AES_256,
				SymmetricKeyAlgorithmTags.AES_192, SymmetricKeyAlgorithmTags.AES_128 });
		signhashgen.setPreferredHashAlgorithms(false, new int[] { HashAlgorithmTags.SHA256, HashAlgorithmTags.SHA1,
				HashAlgorithmTags.SHA384, HashAlgorithmTags.SHA512, HashAlgorithmTags.SHA224, });
		// 3) Request senders add additional checksums to the
		// message (useful when verifying unsigned messages.)
		signhashgen.setFeature(false, Features.FEATURE_MODIFICATION_DETECTION);

		// Create a signature on the encryption subkey.
		PGPSignatureSubpacketGenerator enchashgen = new PGPSignatureSubpacketGenerator();
		// Add metadata to declare its purpose
		enchashgen.setKeyFlags(false, KeyFlags.ENCRYPT_COMMS | KeyFlags.ENCRYPT_STORAGE);

		// Objects used to encrypt the secret key.
		PGPDigestCalculator sha1Calc = new BcPGPDigestCalculatorProvider().get(HashAlgorithmTags.SHA1);
		PGPDigestCalculator sha256Calc = new BcPGPDigestCalculatorProvider().get(HashAlgorithmTags.SHA256);

		// bcpg 1.48 exposes this API that includes s2kcount. Earlier
		// versions use a default of 0x60.
		PBESecretKeyEncryptor pske = (new BcPBESecretKeyEncryptorBuilder(PGPEncryptedData.AES_256, sha256Calc,
				s2kcount)).build(pass.toCharArray());

		// Finally, create the keyring itself. The constructor
		// takes parameters that allow it to generate the self
		// signature.
		PGPKeyRingGenerator keyRingGen = new PGPKeyRingGenerator(PGPSignature.POSITIVE_CERTIFICATION, rsakp_sign, id,
				sha1Calc, signhashgen.generate(), null,
				new BcPGPContentSignerBuilder(rsakp_sign.getPublicKey().getAlgorithm(), HashAlgorithmTags.SHA1), pske);

		// Add our encryption subkey, together with its signature.
		keyRingGen.addSubKey(rsakp_enc, enchashgen.generate(), null);
		return keyRingGen;
	}

	public static PGPSecretKey generateKey(final String keyId, final String passphrase)
			throws IOException, InterruptedException {
		LOG.info("Generating key for id: {}", keyId);

		try {
			final KeyPairGenerator kpg = KeyPairGenerator.getInstance("RSA", "BC");
			kpg.initialize(2048);
			final PGPDigestCalculator sha1Calc = new JcaPGPDigestCalculatorProviderBuilder().build()
					.get(HashAlgorithmTags.SHA1);
			final PGPKeyPair keyPair = new JcaPGPKeyPair(PGPPublicKey.RSA_GENERAL, kpg.generateKeyPair(), new Date());
			final PGPSecretKey secretKey = new PGPSecretKey(PGPSignature.DEFAULT_CERTIFICATION, keyPair, keyId,
					sha1Calc, null, null,
					new JcaPGPContentSignerBuilder(keyPair.getPublicKey().getAlgorithm(), HashAlgorithmTags.SHA1),
					new JcePBESecretKeyEncryptorBuilder(PGPEncryptedData.CAST5, sha1Calc).setProvider("BC")
							.build(passphrase.toCharArray()));
			return secretKey;
		} catch (final NoSuchAlgorithmException | NoSuchProviderException | PGPException e) {
			throw new RepositoryException(e);
		}
	}

	public static void detach_sign(final Path inputFile, final Path outputFile, final GPGInfo gpginfo,
			final boolean sha256) throws IOException, InterruptedException {
		LOG.info("Detach-signing {} with key {} into {}", Util.relativize(inputFile), gpginfo.getKey(),
				Util.relativize(outputFile));

		Files.createDirectories(outputFile.getParent());
		FileUtils.touch(outputFile.toFile());

		try (final FileInputStream sFis = new FileInputStream(inputFile.toFile());
				final BufferedInputStream sBis = new BufferedInputStream(sFis);
				final FileOutputStream os = new FileOutputStream(outputFile.toFile());
				final ArmoredOutputStream aos = new ArmoredOutputStream(os);) {
			final PGPPublicKey publicKey = gpginfo.getPublicKey();
			LOG.trace("publicKey: {}", publicKey);
			final PGPSecretKey secretKey = gpginfo.getSecretKey();
			LOG.trace("secretKey: {}", secretKey);
			final PGPPrivateKey privateKey = gpginfo.getPrivateKey();
			LOG.trace("privateKey: {}", privateKey);
			final PGPSignatureGenerator generator = new PGPSignatureGenerator(
					new JcaPGPContentSignerBuilder(publicKey.getAlgorithm(), sha256 ? PGPUtil.SHA256 : PGPUtil.SHA1)
							.setProvider("BC"));
			LOG.trace("generator: {}", generator);

			generator.init(PGPSignature.BINARY_DOCUMENT, privateKey);
			BCPGOutputStream out = new BCPGOutputStream(aos);

			int ch;
			while ((ch = sBis.read()) >= 0) {
				generator.update((byte) ch);
			}
			sBis.close();

			generator.generate().encode(out);
			out.close();
		} catch (final PGPException e) {
			LOG.error("PGP exception: {}", e.getMessage(), e);
			throw new RepositoryException("Failed to detach-sign " + inputFile, e);
		}
	}

	public static void exportKeyRing(final Path outputFile, final PGPPublicKeyRingCollection keyRing)
			throws IOException {
		try (final FileWriter fw = new FileWriter(outputFile.toFile()); final PemWriter writer = new PemWriter(fw);) {
			writer.writeObject(new PemObject("PGP PUBLIC KEY BLOCK", keyRing.getEncoded()));
		}
	}

	public static GPGInfo fromKeyRing(final Path keyRing, final String keyId, final String password) {
		try (final FileInputStream fis = new FileInputStream(keyRing.toFile());) {
			final PGPSecretKeyRingCollection secretKeyRingCollection = new PGPSecretKeyRingCollection(fis,
					new JcaKeyFingerprintCalculator());
			final Iterator<PGPSecretKeyRing> keyRings = secretKeyRingCollection.getKeyRings(keyId, true, true);
			if (keyRings.hasNext()) {
				final PGPSecretKeyRing secretKeyRing = keyRings.next();
				final List<PGPPublicKey> publicKeys = new ArrayList<>();
				final Iterator<PGPPublicKey> publicKeyIterator = secretKeyRing.getPublicKeys();
				while (publicKeyIterator.hasNext()) {
					publicKeys.add(publicKeyIterator.next());
				}
				final Constructor<PGPPublicKeyRing> constructor = PGPPublicKeyRing.class
						.getDeclaredConstructor(List.class);
				constructor.setAccessible(true);
				final PGPPublicKeyRing publicKeyRing = constructor.newInstance(publicKeys);
				return new GPGInfo(keyId, password, publicKeyRing, secretKeyRing);
			}
			throw new RepositoryException("Unable to locate key " + keyId + " in keyring " + keyRing + "!");
		} catch (final Exception e) {
			throw new RepositoryException(e);
		}
	}

	/*
	 * public static void exportKey(final Path outputFile, final PGPPublicKey
	 * publicKey) throws IOException { try(final FileWriter fw = new
	 * FileWriter(outputFile.toFile()); final PemWriter writer = new
	 * PemWriter(fw);) { writer.writeObject(new
	 * PemObject("PGP PUBLIC KEY BLOCK", publicKey.getEncoded())); } }
	 */

}
