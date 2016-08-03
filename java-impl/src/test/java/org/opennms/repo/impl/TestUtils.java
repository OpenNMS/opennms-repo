package org.opennms.repo.impl;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;

import org.bouncycastle.openpgp.PGPException;
import org.bouncycastle.openpgp.PGPKeyRingGenerator;
import org.bouncycastle.openpgp.PGPPublicKeyRing;
import org.bouncycastle.openpgp.PGPSecretKeyRing;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.RepositoryException;

public abstract class TestUtils {
	public static final Path JRRD1_PATH = Paths.get("target/test-classes/jrrd-1.1.0-1.x86_64.rpm");
	public static final String JRRD1_FILENAME = JRRD1_PATH.getFileName().toString();

	public static final Path JRRD2_PATH = Paths.get("target/test-classes/jrrd-1.1.0-2.el7.centos.x86_64.rpm");
	public static final String JRRD2_FILENAME = JRRD2_PATH.getFileName().toString();

	public static final Path JRRD3_PATH = Paths.get("target/test-classes/jrrd-1.1.0-3.el7.centos.x86_64.rpm");
	public static final String JRRD3_FILENAME = JRRD3_PATH.getFileName().toString();

	private TestUtils() {}

    public static GPGInfo generateGPGInfo() throws IOException, InterruptedException, PGPException {
        final String keyId = "foo@bar.com";
        final String passphrase = "12345";
        try {
        	final PGPKeyRingGenerator generator = GPGUtils.generateKeyRingGenerator(keyId, passphrase, 0x60);
        	final PGPPublicKeyRing publicRing = generator.generatePublicKeyRing();
        	final PGPSecretKeyRing secretRing = generator.generateSecretKeyRing();
	        final GPGInfo gpginfo = new GPGInfo(keyId, passphrase, publicRing, secretRing);
	        return gpginfo;
        } catch (final Throwable t) {
        	throw new RepositoryException("Failed to generate keyring.", t);
        }
    }

    public static void assertFileExists(final String path) {
        final Path p = Paths.get(path);
        assertFileExists(p);
    }

	public static void assertFileExists(final Path path) {
		assertTrue("File/directory '" + path + "' must exist.", path.toFile().exists());
        assertTrue("File/directory '" + path + "' must not be empty.", path.toFile().length() > 0);
	}

    public static void assertFileDoesNotExist(final String path) {
        final Path p = Paths.get(path);
        assertFileDoesNotExist(p);
    }

	public static void assertFileDoesNotExist(final Path path) {
		assertFalse("File/directory '" + path + "' must not exist.", path.toFile().exists());
	}
}
