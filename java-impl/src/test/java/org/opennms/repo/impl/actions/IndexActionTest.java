package org.opennms.repo.impl.actions;

import static org.junit.Assert.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;

import org.apache.commons.io.FileUtils;
import org.junit.Before;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.GPGUtils;
import org.opennms.repo.impl.Options;
import org.opennms.repo.impl.TestUtils;
import org.opennms.repo.impl.rpm.RPMRepository;

public class IndexActionTest {
	private static final Path repositoryRoot = Paths.get("target/commands/index/repositories");
	private GPGInfo m_gpginfo;

	@Before
	public void setUp() throws Exception {
		Util.recursiveDelete(Paths.get("target/commands/index"));
		m_gpginfo = TestUtils.generateGPGInfo();
	}

	@Test
	public void testIndexRPMRepositoryWithoutGPG() throws Exception {
		final Path sourceRoot = repositoryRoot.resolve("testIndexRPMRepositoryWithoutGPG").normalize().toAbsolutePath();
		final Path repodata = sourceRoot.resolve("repodata");

		FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), sourceRoot.toFile());
		TestUtils.assertFileDoesNotExist(repodata);

		final Action action = new IndexAction(new Options(), Arrays.asList("--type", "rpm", sourceRoot.toString()));
		action.run();

        TestUtils.assertFileExists(repodata.resolve("repomd.xml"));

		final RPMRepository sourceRepo = new RPMRepository(sourceRoot);
		assertTrue(sourceRepo.isValid());
	}

	@Test
	public void testIndexRPMRepositoryWithGPG() throws Exception {
		final Path sourceRoot = repositoryRoot.resolve("testIndexRPMRepositoryWithoutGPG").normalize().toAbsolutePath();
		final Path repodata = sourceRoot.resolve("repodata");

		final Path ringPath = Files.createTempFile("secring-", ".gpg");
		m_gpginfo.savePrivateKeyring(ringPath);
		FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), sourceRoot.toFile());
		TestUtils.assertFileDoesNotExist(repodata);

		final Options options = new Options();
		options.setKeyId(m_gpginfo.getKey());
		options.setPassword(m_gpginfo.getPassphrase());
		options.setKeyRing(ringPath);
		final Action action = new IndexAction(options, Arrays.asList("--type", "rpm", sourceRoot.toString()));
		action.run();

        TestUtils.assertFileExists(repodata.resolve("repomd.xml"));

		final RPMRepository sourceRepo = new RPMRepository(sourceRoot);
		assertTrue(sourceRepo.isValid());
	}
}
