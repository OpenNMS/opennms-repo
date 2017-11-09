package org.opennms.repo.impl;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;

import org.bouncycastle.openpgp.PGPException;
import org.bouncycastle.openpgp.PGPKeyRingGenerator;
import org.bouncycastle.openpgp.PGPPublicKeyRing;
import org.bouncycastle.openpgp.PGPSecretKeyRing;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.RepositoryException;

public abstract class TestUtils {
	// A = jicmp, B = jicmp6
	public static final Path A1_I386_PATH = Paths.get("target/test-classes/jicmp-1.4.1-1.i386.rpm");
	public static final String A1_I386_FILENAME = A1_I386_PATH.getFileName().toString();

	public static final Path A1_X64_PATH = Paths.get("target/test-classes/jicmp-1.4.1-1.x86_64.rpm");
	public static final String A1_X64_FILENAME = A1_X64_PATH.getFileName().toString();

	public static final Path A2_I386_PATH = Paths.get("target/test-classes/jicmp-1.4.5-2.i386.rpm");
	public static final String A2_I386_FILENAME = A2_I386_PATH.getFileName().toString();

	public static final Path A2_X64_PATH = Paths.get("target/test-classes/jicmp-1.4.5-2.x86_64.rpm");
	public static final String A2_X64_FILENAME = A2_X64_PATH.getFileName().toString();

	public static final Path A3_I386_PATH = Paths.get("target/test-classes/jicmp-2.0.0-0.1.i386.rpm");
	public static final String A3_I386_FILENAME = A3_I386_PATH.getFileName().toString();

	public static final Path A3_X64_PATH = Paths.get("target/test-classes/jicmp-2.0.0-0.1.x86_64.rpm");
	public static final String A3_X64_FILENAME = A3_X64_PATH.getFileName().toString();

	public static final Path A4_I386_PATH = Paths.get("target/test-classes/jicmp-2.0.0-0.5.i386.rpm");
	public static final String A4_I386_FILENAME = A4_I386_PATH.getFileName().toString();

	public static final Path A4_X64_PATH = Paths.get("target/test-classes/jicmp-2.0.0-0.5.x86_64.rpm");
	public static final String A4_X64_FILENAME = A4_X64_PATH.getFileName().toString();

	public static final Path B1_I386_PATH = Paths.get("target/test-classes/jicmp6-1.2.1-1.i386.rpm");
	public static final String B1_I386_FILENAME = B1_I386_PATH.getFileName().toString();

	public static final Path B1_X64_PATH = Paths.get("target/test-classes/jicmp6-1.2.1-1.x86_64.rpm");
	public static final String B1_X64_FILENAME = B1_X64_PATH.getFileName().toString();

	public static final Path B2_I386_PATH = Paths.get("target/test-classes/jicmp6-1.2.4-1.i386.rpm");
	public static final String B2_I386_FILENAME = B2_I386_PATH.getFileName().toString();

	public static final Path B2_X64_PATH = Paths.get("target/test-classes/jicmp6-1.2.4-1.x86_64.rpm");
	public static final String B2_X64_FILENAME = B2_X64_PATH.getFileName().toString();

	public static final Path B3_I386_PATH = Paths.get("target/test-classes/jicmp6-2.0.0-0.2.i386.rpm");
	public static final String B3_I386_FILENAME = B3_I386_PATH.getFileName().toString();

	public static final Path B3_X64_PATH = Paths.get("target/test-classes/jicmp6-2.0.0-0.2.x86_64.rpm");
	public static final String B3_X64_FILENAME = B3_X64_PATH.getFileName().toString();

	public static final Path B4_I386_PATH = Paths.get("target/test-classes/jicmp6-2.0.0-0.5.i386.rpm");
	public static final String B4_I386_FILENAME = B4_I386_PATH.getFileName().toString();

	public static final Path B4_X64_PATH = Paths.get("target/test-classes/jicmp6-2.0.0-0.5.x86_64.rpm");
	public static final String B4_X64_FILENAME = B4_X64_PATH.getFileName().toString();

	private TestUtils() {
	}

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

	public static void listFiles(final Path path) {
		if (path.toFile().exists()) {
			System.err.println(path);
			final File[] files = path.toFile().listFiles();
			Arrays.sort(files);
			for (final File f : files) {
				if (f.isDirectory()) {
					listFiles(f.toPath());
				} else {
					System.err.println(f.toPath());
				}
			}
		}
	}
}
