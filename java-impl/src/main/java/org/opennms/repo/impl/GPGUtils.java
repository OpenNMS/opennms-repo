package org.opennms.repo.impl;

import java.io.BufferedInputStream;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Path;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.Security;
import java.util.Date;

import org.bouncycastle.bcpg.ArmoredOutputStream;
import org.bouncycastle.bcpg.BCPGOutputStream;
import org.bouncycastle.bcpg.HashAlgorithmTags;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.openpgp.PGPEncryptedData;
import org.bouncycastle.openpgp.PGPException;
import org.bouncycastle.openpgp.PGPKeyPair;
import org.bouncycastle.openpgp.PGPPrivateKey;
import org.bouncycastle.openpgp.PGPPublicKey;
import org.bouncycastle.openpgp.PGPPublicKeyRingCollection;
import org.bouncycastle.openpgp.PGPSecretKey;
import org.bouncycastle.openpgp.PGPSignature;
import org.bouncycastle.openpgp.PGPSignatureGenerator;
import org.bouncycastle.openpgp.PGPUtil;
import org.bouncycastle.openpgp.operator.PGPDigestCalculator;
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

    public static PGPSecretKey generateKey(final String keyId, final String passphrase) throws IOException, InterruptedException {
        LOG.debug("Generating key for id: {}", keyId);

        try {
            final KeyPairGenerator kpg = KeyPairGenerator.getInstance("RSA", "BC");
            kpg.initialize(2048);
            final PGPDigestCalculator sha1Calc = new JcaPGPDigestCalculatorProviderBuilder().build().get(HashAlgorithmTags.SHA1);
            final PGPKeyPair keyPair = new JcaPGPKeyPair(PGPPublicKey.RSA_GENERAL, kpg.generateKeyPair(), new Date());
            final PGPSecretKey secretKey = new PGPSecretKey(PGPSignature.DEFAULT_CERTIFICATION, keyPair, keyId, sha1Calc, null, null, new JcaPGPContentSignerBuilder(keyPair.getPublicKey().getAlgorithm(), HashAlgorithmTags.SHA1), new JcePBESecretKeyEncryptorBuilder(PGPEncryptedData.CAST5, sha1Calc).setProvider("BC").build(passphrase.toCharArray()));
            return secretKey;
        } catch (final NoSuchAlgorithmException | NoSuchProviderException | PGPException e) {
            throw new RepositoryException(e);
        }
    }

    public static void detach_sign(final Path inputFile, final Path outputFile, final GPGInfo gpginfo, final boolean sha256) throws IOException, InterruptedException {
        LOG.debug("Detach-signing {} with key {}", Util.relativize(inputFile), gpginfo.getKey());

        try (
            final FileInputStream sFis = new FileInputStream(inputFile.toFile());
            final BufferedInputStream sBis = new BufferedInputStream(sFis);
            final FileOutputStream os = new FileOutputStream(outputFile.toFile());
            final ArmoredOutputStream aos = new ArmoredOutputStream(os);
        ) {
            final PGPPublicKey publicKey = gpginfo.getPublicKey();
            LOG.debug("publicKey: {}", publicKey);
            final PGPSecretKey secretKey = gpginfo.getSecretKey();
            LOG.debug("secretKey: {}", secretKey);
            final PGPPrivateKey privateKey = gpginfo.getPrivateKey();
            LOG.debug("privateKey: {}", privateKey);
            final PGPSignatureGenerator generator = new PGPSignatureGenerator(new JcaPGPContentSignerBuilder(publicKey.getAlgorithm(), sha256? PGPUtil.SHA256 : PGPUtil.SHA1).setProvider("BC"));
            LOG.debug("generator: {}", generator);

            generator.init(PGPSignature.BINARY_DOCUMENT, privateKey);
            LOG.debug("Generator initialized.");
            BCPGOutputStream out = new BCPGOutputStream(aos);

            int ch;
            while ((ch = sBis.read()) >= 0) {
                generator.update((byte)ch);
            }
            sBis.close();

            LOG.debug("Encoding to output.");
            generator.generate().encode(out);
            LOG.debug("Finished.");
            out.close();
        } catch (final PGPException e) {
            LOG.debug("PGP exception: {}", e.getMessage(), e);
            throw new RepositoryException("Failed to detach-sign " + inputFile, e);
        }
    }

    public static void exportKeyRing(final Path outputFile, final PGPPublicKeyRingCollection keyRing) throws IOException {
        try(final FileWriter fw = new FileWriter(outputFile.toFile()); final PemWriter writer = new PemWriter(fw);) {
            writer.writeObject(new PemObject("PGP PUBLIC KEY BLOCK", keyRing.getEncoded()));
        }
    }

    /*
    public static void exportKey(final Path outputFile, final PGPPublicKey publicKey) throws IOException {
        try(final FileWriter fw = new FileWriter(outputFile.toFile()); final PemWriter writer = new PemWriter(fw);) {
            writer.writeObject(new PemObject("PGP PUBLIC KEY BLOCK", publicKey.getEncoded()));
        }
    }
    */

}
