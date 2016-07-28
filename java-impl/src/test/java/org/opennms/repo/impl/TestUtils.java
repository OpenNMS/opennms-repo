package org.opennms.repo.impl;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;

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
