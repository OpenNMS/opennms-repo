package org.opennms.repo.impl.rpm;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.FileTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;

import org.apache.commons.io.FileUtils;
import org.apache.commons.io.IOUtils;
import org.junit.Before;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.MetaRepository;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.Util;
import org.opennms.repo.api.Version;
import org.opennms.repo.impl.TestUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMMetaRepositoryTest {
	private static final Logger LOG = LoggerFactory.getLogger(RPMMetaRepositoryTest.class);

	private GPGInfo m_gpginfo;

	@Before
	public void setUp() throws Exception {
		Util.recursiveDelete(Paths.get("target/repositories"));
		m_gpginfo = TestUtils.generateGPGInfo();
	}

	@Test
	public void testCreateEmptyMetaRepository() throws Exception {
		final String repositoryPath = "target/repositories/RPMMetaRepositoryTest.testCreateEmptyMetaRepository";

		RPMMetaRepository repo = new RPMMetaRepository(Paths.get(repositoryPath));
		assertFalse(repo.isValid());

		repo.index(m_gpginfo);
		TestUtils.assertFileExists(repositoryPath + "/common/repodata");
		TestUtils.assertFileExists(repositoryPath + "/common/repodata/repomd.xml");
		TestUtils.assertFileExists(repositoryPath + "/common/repodata/repomd.xml.asc");
		TestUtils.assertFileExists(repositoryPath + "/common/repodata/repomd.xml.key");
	}

	@Test
	public void testAddRPMsToMetaRepository() throws Exception {
		final String repositoryPath = "target/repositories/RPMMetaRepositoryTest.testAddRPMsToMetaRepository";
		Repository repo = new RPMMetaRepository(Paths.get(repositoryPath));
		assertFalse(repo.isValid());

		final Path outputPath = Paths.get(repositoryPath).resolve("common").resolve("amd64");
		final File packageA1File = new File(outputPath.toFile(), TestUtils.A1_X64_FILENAME);
		final File packageA2File = new File(outputPath.toFile(), TestUtils.A2_X64_FILENAME);
		final File packageA3File = new File(outputPath.toFile(), TestUtils.A3_X64_FILENAME);

		final RPMPackage packageA1 = RPMUtils.getPackage(TestUtils.A1_X64_PATH);
		final RPMPackage packageA2 = RPMUtils.getPackage(TestUtils.A2_X64_PATH);
		final RPMPackage packageA3 = RPMUtils.getPackage(TestUtils.A3_X64_PATH);
		repo.addPackages(packageA1, packageA2, packageA3);
		repo.index(m_gpginfo);

		final DeltaRPM drpm = new DeltaRPM(packageA1, packageA3);
		final Path drpmPath = outputPath.resolve("..").resolve("drpms");
		TestUtils.assertFileExists(drpm.getFilePath(drpmPath));
		TestUtils.assertFileExists(packageA1File.toPath());
		TestUtils.assertFileExists(packageA2File.toPath());
		TestUtils.assertFileExists(packageA3File.toPath());
	}

	@Test
	public void testAddRPMsToMetaSubRepository() throws Exception {
		final String repositoryPath = "target/repositories/RPMMetaRepositoryTest.testAddRPMsToMetaSubRepository";
		MetaRepository repo = new RPMMetaRepository(Paths.get(repositoryPath));
		assertFalse(repo.isValid());

		final Path outputPath = Paths.get(repositoryPath).resolve("rhel5").resolve("amd64");
		final File packageA1File = new File(outputPath.toFile(), TestUtils.A1_X64_FILENAME);
		final File packageA2File = new File(outputPath.toFile(), TestUtils.A2_X64_FILENAME);
		final File packageA3File = new File(outputPath.toFile(), TestUtils.A3_X64_FILENAME);

		repo.addPackages("rhel5", RPMUtils.getPackage(TestUtils.A1_X64_PATH), RPMUtils.getPackage(TestUtils.A2_X64_PATH), RPMUtils.getPackage(TestUtils.A3_X64_PATH));
		repo.index(m_gpginfo);

		final RPMPackage packageA1 = RPMUtils.getPackage(packageA1File);
		final RPMPackage packageA2 = RPMUtils.getPackage(packageA2File);
		final RPMPackage packageA3 = RPMUtils.getPackage(packageA3File);
		final Path drpmPath = outputPath.resolve("..").resolve("drpms").normalize().toAbsolutePath();

		TestUtils.assertFileExists(new DeltaRPM(packageA1, packageA3).getFilePath(drpmPath));
		TestUtils.assertFileExists(new DeltaRPM(packageA2, packageA3).getFilePath(drpmPath));
		TestUtils.assertFileExists(packageA1File.toPath());
		TestUtils.assertFileExists(packageA2File.toPath());
		TestUtils.assertFileExists(packageA3File.toPath());
	}

	@Test
	public void testCreateRepositoryWithRPMs() throws Exception {
		final String repositoryPath = "target/repositories/RPMMetaRepositoryTest.testCreateRepositoryWithRPMs";
		Repository repo = new RPMMetaRepository(Paths.get(repositoryPath));
		assertFalse(repo.isValid());

		final Path repositoryDir = Paths.get(repositoryPath).resolve("common").resolve("amd64");
		Files.createDirectories(Paths.get(repositoryPath));
		final File repositoryFile = repositoryDir.toFile();
		final File packageA1File = new File(repositoryFile, TestUtils.A1_X64_FILENAME);
		final File packageA2File = new File(repositoryFile, TestUtils.A2_X64_FILENAME);
		final File packageA3File = new File(repositoryFile, TestUtils.A3_X64_FILENAME);

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), repositoryFile);
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), repositoryFile);
		FileUtils.copyFileToDirectory(TestUtils.A3_X64_PATH.toFile(), repositoryFile);

		TestUtils.assertFileExists(packageA1File.toPath());
		TestUtils.assertFileExists(packageA2File.toPath());
		TestUtils.assertFileExists(packageA3File.toPath());

		repo.index(m_gpginfo);

		final RPMPackage packageA1 = RPMUtils.getPackage(packageA1File);
		final RPMPackage packageA2 = RPMUtils.getPackage(packageA2File);
		final RPMPackage packageA3 = RPMUtils.getPackage(packageA3File);

		TestUtils.assertFileExists(repositoryPath + "/common/repodata");
		TestUtils.assertFileExists(repositoryPath + "/common/repodata/repomd.xml");
		TestUtils.assertFileExists(repositoryPath + "/common/repodata/repomd.xml.asc");
		TestUtils.assertFileExists(repositoryPath + "/common/repodata/repomd.xml.key");
		TestUtils.assertFileExists(repositoryPath + "/common/drpms/" + new DeltaRPM(packageA1, packageA3).getFileName());
		TestUtils.assertFileExists(repositoryPath + "/common/drpms/" + new DeltaRPM(packageA2, packageA3).getFileName());

		final List<String> lines = new ArrayList<>();
		Files.walk(Paths.get(repositoryPath).resolve("common").resolve("repodata")).forEach(path -> {
			if (path.toString().contains("-filelists.xml")) {
				try (final FileInputStream fis = new FileInputStream(path.toFile());
						final GZIPInputStream gis = new GZIPInputStream(fis);
						final InputStreamReader isr = new InputStreamReader(gis)) {
					lines.addAll(IOUtils.readLines(gis, Charset.defaultCharset()));
				} catch (final IOException e) {
					LOG.debug("faild to read from {}", path, e);
				}
				;
			}
		});

		final Pattern packagesPattern = Pattern.compile(".*packages=\"(\\d+)\".*");
		final Pattern versionPattern = Pattern
				.compile("\\s*<version epoch=\"(\\d+)\" ver=\"([^\"]*)\" rel=\"([^\\\"]*)\"/>\\s*");
		assertTrue("There should be data in *-filelists.xml.gz", lines.size() > 0);
		int packages = 0;
		final Set<Version> versions = new TreeSet<>();
		for (final String line : lines) {
			final Matcher packagesMatcher = packagesPattern.matcher(line);
			final Matcher versionMatcher = versionPattern.matcher(line);
			if (packagesMatcher.matches()) {
				packages = Integer.valueOf(packagesMatcher.group(1));
			} else if (versionMatcher.matches()) {
				final int epoch = Integer.valueOf(versionMatcher.group(1)).intValue();
				final String version = versionMatcher.group(2);
				final String release = versionMatcher.group(3);
				versions.add(new RPMVersion(epoch, version, release));
			} else {
				// LOG.debug("Does not match: {}", line);
			}
		}

		assertEquals("There should be 3 packages in the file list.", 3, packages);
		final Iterator<Version> it = versions.iterator();

		assertTrue(it.hasNext());
		Version v = it.next();
		assertEquals(new RPMVersion(0, "1.4.1", "1"), v);

		assertTrue(it.hasNext());
		v = it.next();
		assertEquals(new RPMVersion(0, "1.4.5", "2"), v);

		assertTrue(it.hasNext());
		v = it.next();
		assertEquals(new RPMVersion(0, "2.0.0", "0.1"), v);
	}

	@Test
	public void testCreateRepositoryNoUpdates() throws Exception {
		final String repositoryPath = "target/repositories/RPMMetaRepositoryTest.testCreateRepositoryNoUpdates";
		Repository repo = new RPMMetaRepository(Paths.get(repositoryPath));
		assertFalse(repo.isValid());

		final Path commonPath = Paths.get(repositoryPath).resolve("common");
		final Path archPath = commonPath.resolve("amd64");
		Files.createDirectories(archPath);
		Files.createDirectories(Paths.get(repositoryPath));
		final File packageA1File = new File(archPath.toFile(), TestUtils.A1_X64_FILENAME);
		final File packageA2File = new File(archPath.toFile(), TestUtils.A2_X64_FILENAME);
		final File packageA3File = new File(archPath.toFile(), TestUtils.A3_X64_FILENAME);

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), archPath.toFile());
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), archPath.toFile());
		FileUtils.copyFileToDirectory(TestUtils.A3_X64_PATH.toFile(), archPath.toFile());

		TestUtils.assertFileExists(packageA1File.toPath());
		TestUtils.assertFileExists(packageA2File.toPath());
		TestUtils.assertFileExists(packageA3File.toPath());

		repo.index(m_gpginfo);

		final Path repodata = commonPath.resolve("repodata");
		final Path drpms = commonPath.resolve("drpms");

		final RPMPackage packageA1 = RPMUtils.getPackage(packageA1File);
		final RPMPackage packageA2 = RPMUtils.getPackage(packageA2File);
		final RPMPackage packageA3 = RPMUtils.getPackage(packageA3File);

		final DeltaRPM delta13 = new DeltaRPM(packageA1, packageA3);
		final DeltaRPM delta23 = new DeltaRPM(packageA2, packageA3);

		TestUtils.assertFileExists(repodata.resolve("repomd.xml"));
		TestUtils.assertFileExists(repodata.resolve("repomd.xml.asc"));
		TestUtils.assertFileExists(repodata.resolve("repomd.xml.key"));
		TestUtils.assertFileExists(delta13.getFilePath(drpms));
		TestUtils.assertFileExists(delta23.getFilePath(drpms));

		final Map<Path, FileTime> fileTimes = new HashMap<>();
		final Path[] repositoryPaths = new Path[] {
			repodata.resolve("repomd.xml"),
			repodata.resolve("repomd.xml.asc"),
			repodata.resolve("repomd.xml.key"),
			drpms.resolve(delta13.getFileName()),
			drpms.resolve(delta23.getFileName())
		};

		for (final Path p : repositoryPaths) {
			fileTimes.put(p, Util.getFileTime(p));
		}

		repo.index(m_gpginfo);

		for (final Path p : repositoryPaths) {
			assertEquals(p + " time should not have changed after a reindex", fileTimes.get(p), Util.getFileTime(p));
		}
	}

	@Test
	public void testAddPackages() throws Exception {
		final String sourceRepositoryPath = "target/repositories/RPMMetaRepositoryTest.testAddPackages/source";
		final String targetRepositoryPath = "target/repositories/RPMMetaRepositoryTest.testAddPackages/target";
		Repository sourceRepo = new RPMMetaRepository(Paths.get(sourceRepositoryPath));
		Repository targetRepo = new RPMMetaRepository(Paths.get(targetRepositoryPath));

		final Path sourceRepositoryCommon = Paths.get(sourceRepositoryPath).resolve("common");
		final Path targetRepositoryCommon = Paths.get(targetRepositoryPath).resolve("common");
		Files.createDirectories(sourceRepositoryCommon.resolve("amd64"));
		Files.createDirectories(targetRepositoryCommon.resolve("amd64"));
		final File packageA1TargetFile = new File(targetRepositoryCommon.resolve("amd64").toFile(),
				TestUtils.A1_X64_FILENAME);
		final File packageA2SourceFile = new File(sourceRepositoryCommon.resolve("amd64").toFile(),
				TestUtils.A2_X64_FILENAME);
		final Path packageA2TargetFile = targetRepositoryCommon.resolve("amd64").resolve(TestUtils.A2_X64_FILENAME);

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(),
				new File(targetRepositoryCommon.toFile(), "amd64"));
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(),
				new File(sourceRepositoryCommon.toFile(), "amd64"));

		TestUtils.assertFileExists(packageA1TargetFile.toPath());
		TestUtils.assertFileExists(packageA2SourceFile.toPath());
		TestUtils.assertFileDoesNotExist(packageA2TargetFile);

		targetRepo.addPackages(sourceRepo);
		TestUtils.assertFileExists(packageA2TargetFile);
	}

	@Test
	public void testAddPackagesToSubrepo() throws Exception {
		final String sourceRepositoryPath = "target/repositories/RPMMetaRepositoryTest.testAddPackagesToSubrepo/source";
		final String targetRepositoryPath = "target/repositories/RPMMetaRepositoryTest.testAddPackagesToSubrepo/target";
		MetaRepository sourceRepo = new RPMMetaRepository(Paths.get(sourceRepositoryPath));
		MetaRepository targetRepo = new RPMMetaRepository(Paths.get(targetRepositoryPath));

		final Path sourceRepositoryCommon = Paths.get(sourceRepositoryPath).resolve("rhel5");
		final Path targetRepositoryCommon = Paths.get(targetRepositoryPath).resolve("rhel5");
		Files.createDirectories(sourceRepositoryCommon.resolve("amd64"));
		Files.createDirectories(targetRepositoryCommon.resolve("amd64"));
		final File packageA1TargetFile = new File(targetRepositoryCommon.resolve("amd64").toFile(),
				TestUtils.A1_X64_FILENAME);
		final File packageA2SourceFile = new File(sourceRepositoryCommon.resolve("amd64").toFile(),
				TestUtils.A2_X64_FILENAME);
		final Path packageA2TargetFile = targetRepositoryCommon.resolve("amd64").resolve(TestUtils.A2_X64_FILENAME);

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(),
				new File(targetRepositoryCommon.toFile(), "amd64"));
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(),
				new File(sourceRepositoryCommon.toFile(), "amd64"));

		TestUtils.assertFileExists(packageA1TargetFile.toPath());
		TestUtils.assertFileExists(packageA2SourceFile.toPath());
		TestUtils.assertFileDoesNotExist(packageA2TargetFile);

		targetRepo.addPackages("rhel5", sourceRepo);
		TestUtils.assertFileExists(packageA2TargetFile);
	}

	@Test
	public void testAddOldPackages() throws Exception {
		final String sourceRepositoryPath = "target/repositories/RPMMetaRepositoryTest.testAddOldPackages/source";
		final String targetRepositoryPath = "target/repositories/RPMMetaRepositoryTest.testAddOldPackages/target";
		Repository sourceRepo = new RPMMetaRepository(Paths.get(sourceRepositoryPath));
		Repository targetRepo = new RPMMetaRepository(Paths.get(targetRepositoryPath));

		final Path sourceRepositoryCommonPath = Paths.get(sourceRepositoryPath).resolve("common");
		final Path targetRepositoryCommonPath = Paths.get(targetRepositoryPath).resolve("common");
		final Path sourceArchPath = sourceRepositoryCommonPath.resolve("amd64");
		final Path targetArchPath = targetRepositoryCommonPath.resolve("amd64");
		Files.createDirectories(sourceArchPath);
		Files.createDirectories(targetArchPath);
		final File packageASourceFile = new File(sourceArchPath.toFile(), TestUtils.A1_X64_FILENAME);
		final File packageATargetFile = new File(targetArchPath.toFile(), TestUtils.A2_X64_FILENAME);
		final String packageA1TargetFile = targetArchPath.resolve(TestUtils.A1_X64_FILENAME).toString();

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), sourceArchPath.toFile());
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), targetArchPath.toFile());

		TestUtils.assertFileExists(packageASourceFile.toPath());
		TestUtils.assertFileExists(packageATargetFile.toPath());
		TestUtils.assertFileDoesNotExist(packageA1TargetFile);

		targetRepo.addPackages(sourceRepo);
		TestUtils.assertFileDoesNotExist(packageA1TargetFile);
	}

	@Test
	public void testInheritedRepository() throws Exception {
		final String sourceRepositoryPath = "target/repositories/RPMMetaRepositoryTest.testInheritedRepository/source";
		final String targetRepositoryPath = "target/repositories/RPMMetaRepositoryTest.testInheritedRepository/target";

		final Path sourceCommonPath = Paths.get(sourceRepositoryPath).resolve("common");
		final Path targetCommonPath = Paths.get(targetRepositoryPath).resolve("common");
		final Path sourceArchPath = sourceCommonPath.resolve("amd64");
		final Path targetArchPath = targetCommonPath.resolve("amd64");

		Files.createDirectories(sourceArchPath);
		Files.createDirectories(targetArchPath);

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), targetArchPath.toFile());
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), sourceArchPath.toFile());

		Repository sourceRepo = new RPMMetaRepository(Paths.get(sourceRepositoryPath));
		Repository targetRepo = new RPMMetaRepository(Paths.get(targetRepositoryPath), Util.newSortedSet(sourceRepo));

		final String packageA2TargetPath = targetArchPath.resolve(TestUtils.A2_X64_FILENAME).toString();
		TestUtils.assertFileDoesNotExist(packageA2TargetPath);

		targetRepo.index(m_gpginfo);
		TestUtils.assertFileExists(packageA2TargetPath);
	}

	@Test
	public void testClone() throws Exception {
		final Path sourceRepositoryPath = Paths.get("target/repositories/RPMMetaRepositoryTest.testClone/source");
		final Path targetRepositoryPath = Paths.get("target/repositories/RPMMetaRepositoryTest.testClone/target");
		final Path sourceArchPath = sourceRepositoryPath.resolve("common").resolve("amd64");
		final Path targetArchPath = targetRepositoryPath.resolve("common").resolve("amd64");

		Files.createDirectories(sourceArchPath);
		Files.createDirectories(targetArchPath);

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), targetArchPath.toFile());
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), sourceArchPath.toFile());
		FileUtils.copyFileToDirectory(TestUtils.A3_X64_PATH.toFile(), sourceArchPath.toFile());

		Repository sourceRepo = new RPMMetaRepository(sourceRepositoryPath);
		Repository targetRepo = new RPMMetaRepository(targetRepositoryPath);
		sourceRepo.index(m_gpginfo);
		targetRepo.index(m_gpginfo);

		final Path packageA1TargetPath = targetArchPath.resolve(TestUtils.A1_X64_FILENAME);
		final Path packageA2TargetPath = targetArchPath.resolve(TestUtils.A2_X64_FILENAME);
		final Path packageA3TargetPath = targetArchPath.resolve(TestUtils.A3_X64_FILENAME);
		TestUtils.assertFileExists(packageA1TargetPath);
		TestUtils.assertFileDoesNotExist(packageA2TargetPath);
		TestUtils.assertFileDoesNotExist(packageA3TargetPath);

		sourceRepo.cloneInto(targetRepositoryPath);
		targetRepo.index(m_gpginfo);

		TestUtils.assertFileDoesNotExist(packageA1TargetPath);
		TestUtils.assertFileExists(packageA2TargetPath);
		TestUtils.assertFileExists(packageA3TargetPath);
	}
}
