package org.opennms.repo.impl.actions;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Collection;

import org.apache.commons.io.FileUtils;
import org.junit.Before;
import org.junit.BeforeClass;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.Options;
import org.opennms.repo.impl.TestUtils;
import org.opennms.repo.impl.rpm.RPMMetaRepository;
import org.opennms.repo.impl.rpm.RPMRepository;
import org.opennms.repo.impl.rpm.RPMUtils;

public class NormalizeActionTest {
	private static final Path repositoryRoot = Paths.get("target/commands/normalize/repositories");

	private static GPGInfo s_gpginfo;
	private static Path s_ringPath;

	@BeforeClass
	public static void createGPG() throws Exception {
		s_gpginfo = TestUtils.generateGPGInfo();
		s_ringPath = Files.createTempFile("secring-", ".gpg");
		s_ringPath.toFile().deleteOnExit();
		s_gpginfo.savePrivateKeyring(s_ringPath);
	}

	@Before
	public void setUp() throws Exception {
		Util.recursiveDelete(Paths.get("target/commands/normalize"));
	}

	@Test
	public void testNormalizeRepository() throws Exception {
		final Path sourceRoot = repositoryRoot.resolve("testNormalizeRepository").normalize().toAbsolutePath();
		final Path repodata = sourceRoot.resolve("repodata");

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), sourceRoot.toFile());
		TestUtils.assertFileDoesNotExist(repodata);

		new RPMRepository(sourceRoot).refresh();

		final Options options = new Options("normalize");
		final Action action = new NormalizeAction(options, Arrays.asList(sourceRoot.toString()));
		action.run();

		TestUtils.assertFileExists(sourceRoot.resolve("rpms").resolve("jicmp").resolve("x86_64").resolve(TestUtils.A1_X64_FILENAME));

		final RPMRepository sourceRepo = new RPMRepository(sourceRoot);
		assertTrue(sourceRepo.isValid());
	}

	@Test
	public void testNormalizeMetaRepository() throws Exception {
		final Path packageRoot = repositoryRoot.resolve("testNormalizeMetaRepository").normalize().toAbsolutePath();
		final Path repodata = packageRoot.resolve("repodata");

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), packageRoot.resolve("common").toFile());
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), packageRoot.resolve("rhel6").toFile());
		FileUtils.copyFileToDirectory(TestUtils.B3_X64_PATH.toFile(), packageRoot.resolve("rhel7").toFile());
		FileUtils.copyFileToDirectory(TestUtils.B4_X64_PATH.toFile(), packageRoot.resolve("rhel7").toFile());
		TestUtils.assertFileDoesNotExist(repodata);

		new RPMMetaRepository(packageRoot).index(s_gpginfo);

		final Options options = new Options("normalize");
		final Action action = new NormalizeAction(options, Arrays.asList(packageRoot.toString()));
		action.run();

		final Path a1path = packageRoot.resolve("common").resolve("rpms").resolve("jicmp").resolve("x86_64").resolve(TestUtils.A1_X64_FILENAME);
		final Path a2path = packageRoot.resolve("rhel6").resolve("rpms").resolve("jicmp").resolve("x86_64").resolve(TestUtils.A2_X64_FILENAME);
		final Path b3path = packageRoot.resolve("rhel7").resolve("rpms").resolve("jicmp6").resolve("x86_64").resolve(TestUtils.B3_X64_FILENAME);
		final Path b4path = packageRoot.resolve("rhel7").resolve("rpms").resolve("jicmp6").resolve("x86_64").resolve(TestUtils.B4_X64_FILENAME);

		TestUtils.assertFileExists(a1path);
		TestUtils.assertFileExists(a2path);
		TestUtils.assertFileExists(b3path);
		TestUtils.assertFileExists(b4path);

		final RPMMetaRepository sourceRepo = new RPMMetaRepository(packageRoot);
		assertTrue(sourceRepo.isValid());

		final Collection<RepositoryPackage> packages = sourceRepo.getPackages();
		assertEquals(4, packages.size());
		assertTrue(packages.contains(RPMUtils.getPackage(a1path)));
		assertTrue(packages.contains(RPMUtils.getPackage(a2path)));
		assertTrue(packages.contains(RPMUtils.getPackage(b3path)));
		assertTrue(packages.contains(RPMUtils.getPackage(b4path)));
	}

	@Test
	public void normalizeWithEmptyDirectories() throws Exception {
		final Path packageRoot = repositoryRoot.resolve("testNormalizeWithEmptyDirectoriesMetaRepository").normalize().toAbsolutePath();
		final Path repodata = packageRoot.resolve("repodata");

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), packageRoot.resolve("junk").toFile());
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), packageRoot.resolve("junk").toFile());
		FileUtils.copyFileToDirectory(TestUtils.B3_X64_PATH.toFile(), packageRoot.resolve("crap").toFile());
		FileUtils.copyFileToDirectory(TestUtils.B4_X64_PATH.toFile(), packageRoot.resolve("crap").toFile());
		TestUtils.assertFileDoesNotExist(repodata);

		new RPMRepository(packageRoot).index(s_gpginfo);

		final Options options = new Options("normalize");
		final Action action = new NormalizeAction(options, Arrays.asList(packageRoot.toString()));
		action.run();

		final Path a1path = packageRoot.resolve("rpms").resolve("jicmp").resolve("x86_64").resolve(TestUtils.A1_X64_FILENAME);
		final Path a2path = packageRoot.resolve("rpms").resolve("jicmp").resolve("x86_64").resolve(TestUtils.A2_X64_FILENAME);
		final Path b3path = packageRoot.resolve("rpms").resolve("jicmp6").resolve("x86_64").resolve(TestUtils.B3_X64_FILENAME);
		final Path b4path = packageRoot.resolve("rpms").resolve("jicmp6").resolve("x86_64").resolve(TestUtils.B4_X64_FILENAME);

		TestUtils.assertFileExists(a1path);
		TestUtils.assertFileExists(a2path);
		TestUtils.assertFileExists(b3path);
		TestUtils.assertFileExists(b4path);

		final RPMRepository sourceRepo = new RPMRepository(packageRoot);
		assertTrue(sourceRepo.isValid());

		final Collection<RepositoryPackage> packages = sourceRepo.getPackages();
		assertEquals(4, packages.size());
		assertTrue(packages.contains(RPMUtils.getPackage(a1path)));
		assertTrue(packages.contains(RPMUtils.getPackage(a2path)));
		assertTrue(packages.contains(RPMUtils.getPackage(b3path)));
		assertTrue(packages.contains(RPMUtils.getPackage(b4path)));

		TestUtils.assertFileDoesNotExist(packageRoot.resolve("crap"));
		TestUtils.assertFileDoesNotExist(packageRoot.resolve("junk"));
	}
}
