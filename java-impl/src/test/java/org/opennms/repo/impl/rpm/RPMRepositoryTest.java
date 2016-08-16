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
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.Util;
import org.opennms.repo.api.Version;
import org.opennms.repo.impl.TestUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMRepositoryTest {
	private static final Logger LOG = LoggerFactory.getLogger(RPMRepositoryTest.class);

	private GPGInfo m_gpginfo;

	@Before
	public void setUp() throws Exception {
		Util.recursiveDelete(Paths.get("target/repositories"));
		m_gpginfo = TestUtils.generateGPGInfo();
	}

	@Test
	public void testCreateEmptyRepository() throws Exception {
		final String repositoryPath = "target/repositories/RPMRepositoryTest.testCreateEmptyRepository";
		Repository repo = new RPMRepository(Paths.get(repositoryPath));
		assertFalse(repo.isValid());

		repo.index(m_gpginfo);
		TestUtils.assertFileExists(repositoryPath + "/repodata");
		TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml");
		TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.asc");
		TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.key");
	}

	@Test
	public void testAddRPMsToRepository() throws Exception {
		final String repositoryPath = "target/repositories/RPMRepositoryTest.testAddRPMsToRepository";
		Repository repo = new RPMRepository(Paths.get(repositoryPath));
		assertFalse(repo.isValid());

		final Path outputPath = Paths.get(repositoryPath).resolve("amd64");
		final File packageA1File = new File(outputPath.toFile(), TestUtils.A1_X64_FILENAME);
		final File packageA2File = new File(outputPath.toFile(), TestUtils.A2_X64_FILENAME);
		final File packageA3File = new File(outputPath.toFile(), TestUtils.A3_X64_FILENAME);

		repo.addPackages(RPMUtils.getPackage(TestUtils.A1_X64_PATH.toFile()),
				RPMUtils.getPackage(TestUtils.A2_X64_PATH.toFile()), RPMUtils.getPackage(TestUtils.A3_X64_PATH.toFile()));
		repo.index(m_gpginfo);

		final RPMPackage packageA1 = RPMUtils.getPackage(packageA1File);
		final RPMPackage packageA2 = RPMUtils.getPackage(packageA2File);
		final RPMPackage packageA3 = RPMUtils.getPackage(packageA3File);

		TestUtils.assertFileExists(repositoryPath + "/drpms/" + new DeltaRPM(packageA1, packageA3).getFileName());
		TestUtils.assertFileExists(repositoryPath + "/drpms/" + new DeltaRPM(packageA2, packageA3).getFileName());
		TestUtils.assertFileExists(packageA1File.getAbsolutePath());
		TestUtils.assertFileExists(packageA2File.getAbsolutePath());
		TestUtils.assertFileExists(packageA3File.getAbsolutePath());
	}

	@Test
	public void testCreateRepositoryWithRPMs() throws Exception {
		final String repositoryPath = "target/repositories/RPMRepositoryTest.testCreateRepositoryWithRPMs";
		Repository repo = new RPMRepository(Paths.get(repositoryPath));
		assertFalse(repo.isValid());

		final File repositoryDir = new File(repositoryPath);
		Files.createDirectories(Paths.get(repositoryPath));
		final File packageA1File = new File(repositoryDir, TestUtils.A1_X64_FILENAME);
		final File packageA2File = new File(repositoryDir, TestUtils.A2_X64_FILENAME);
		final File packageA3File = new File(repositoryDir, TestUtils.A3_X64_FILENAME);

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), repositoryDir);
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), repositoryDir);
		FileUtils.copyFileToDirectory(TestUtils.A3_X64_PATH.toFile(), repositoryDir);

		TestUtils.assertFileExists(packageA1File.getPath());
		TestUtils.assertFileExists(packageA2File.getPath());
		TestUtils.assertFileExists(packageA3File.getPath());

		final GPGInfo gpginfo = TestUtils.generateGPGInfo();
		repo.index(gpginfo);

		final RPMPackage packageA1 = RPMUtils.getPackage(packageA1File);
		final RPMPackage packageA2 = RPMUtils.getPackage(packageA2File);
		final RPMPackage packageA3 = RPMUtils.getPackage(packageA3File);

		TestUtils.assertFileExists(repositoryPath + "/repodata");
		TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml");
		TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.asc");
		TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.key");
		TestUtils.assertFileExists(repositoryPath + "/drpms/" + new DeltaRPM(packageA1, packageA3).getFileName());
		TestUtils.assertFileExists(repositoryPath + "/drpms/" + new DeltaRPM(packageA2, packageA3).getFileName());

		final List<String> lines = new ArrayList<>();
		Files.walk(Paths.get(repositoryPath).resolve("repodata")).forEach(path -> {
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
		final String repositoryPath = "target/repositories/RPMRepositoryTest.testCreateRepositoryNoUpdates";
		Repository repo = new RPMRepository(Paths.get(repositoryPath));
		assertFalse(repo.isValid());

		final File repositoryDir = new File(repositoryPath);
		Files.createDirectories(Paths.get(repositoryPath));
		final File packageA1File = new File(repositoryDir, TestUtils.A1_X64_FILENAME);
		final File packageA2File = new File(repositoryDir, TestUtils.A2_X64_FILENAME);
		final File packageA3File = new File(repositoryDir, TestUtils.A3_X64_FILENAME);

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), repositoryDir);
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), repositoryDir);
		FileUtils.copyFileToDirectory(TestUtils.A3_X64_PATH.toFile(), repositoryDir);

		TestUtils.assertFileExists(packageA1File.getPath());
		TestUtils.assertFileExists(packageA2File.getPath());
		TestUtils.assertFileExists(packageA3File.getPath());

		final GPGInfo gpginfo = TestUtils.generateGPGInfo();
		repo.index(gpginfo);

		final RPMPackage packageA1 = RPMUtils.getPackage(packageA1File);
		final RPMPackage packageA2 = RPMUtils.getPackage(packageA2File);
		final RPMPackage packageA3 = RPMUtils.getPackage(packageA3File);

		final DeltaRPM deltaA13 = new DeltaRPM(packageA1, packageA3);
		final DeltaRPM deltaA23 = new DeltaRPM(packageA2, packageA3);

		TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml");
		TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.asc");
		TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.key");
		TestUtils.assertFileExists(repositoryPath + "/drpms/" + deltaA13.getFileName());
		TestUtils.assertFileExists(repositoryPath + "/drpms/" + deltaA23.getFileName());

		final Path repodata = Paths.get(repositoryPath).resolve("repodata");
		final Path drpms = Paths.get(repositoryPath).resolve("drpms");

		final Map<Path, FileTime> fileTimes = new HashMap<>();
		final Path[] repositoryPaths = new Path[] {
			repodata.resolve("repomd.xml"),
			repodata.resolve("repomd.xml.asc"),
			repodata.resolve("repomd.xml.key"),
			deltaA13.getFilePath(drpms),
			deltaA23.getFilePath(drpms)
		};

		for (final Path p : repositoryPaths) {
			fileTimes.put(p, Util.getFileTime(p));
		}

		repo = new RPMRepository(Paths.get(repositoryPath));
		repo.index(gpginfo);

		for (final Path p : repositoryPaths) {
			assertEquals(p + " time should not have changed after a reindex", fileTimes.get(p).toMillis(),
					Util.getFileTime(p).toMillis());
		}
	}

	@Test
	public void testAddPackages() throws Exception {
		final String sourceRepositoryPath = "target/repositories/RPMRepositoryTest.testAddPackages/source";
		final String targetRepositoryPath = "target/repositories/RPMRepositoryTest.testAddPackages/target";
		Repository sourceRepo = new RPMRepository(Paths.get(sourceRepositoryPath));
		Repository targetRepo = new RPMRepository(Paths.get(targetRepositoryPath));

		final File sourceRepositoryDir = new File(sourceRepositoryPath);
		final File targetRepositoryDir = new File(targetRepositoryPath);
		Files.createDirectories(Paths.get(sourceRepositoryPath));
		Files.createDirectories(Paths.get(targetRepositoryPath));
		final File packageA1TargetFile = new File(new File(targetRepositoryDir, "amd64"), TestUtils.A1_X64_FILENAME);
		final File packageA2SourceFile = new File(new File(sourceRepositoryDir, "amd64"), TestUtils.A2_X64_FILENAME);
		final String packageA2TargetFile = targetRepositoryDir + File.separator + "amd64" + File.separator
				+ TestUtils.A2_X64_FILENAME;

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), new File(targetRepositoryDir, "amd64"));
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), new File(sourceRepositoryDir, "amd64"));

		TestUtils.assertFileExists(packageA1TargetFile.getAbsolutePath());
		TestUtils.assertFileExists(packageA2SourceFile.getAbsolutePath());
		TestUtils.assertFileDoesNotExist(packageA2TargetFile);

		targetRepo.addPackages(sourceRepo);
		TestUtils.assertFileExists(packageA2TargetFile);
	}

	@Test
	public void testAddOldPackages() throws Exception {
		final String sourceRepositoryPath = "target/repositories/RPMRepositoryTest.testAddOldPackages/source";
		final String targetRepositoryPath = "target/repositories/RPMRepositoryTest.testAddOldPackages/target";
		Repository sourceRepo = new RPMRepository(Paths.get(sourceRepositoryPath));
		Repository targetRepo = new RPMRepository(Paths.get(targetRepositoryPath));

		final File sourceRepositoryDir = new File(sourceRepositoryPath);
		final File targetRepositoryDir = new File(targetRepositoryPath);
		Files.createDirectories(Paths.get(sourceRepositoryPath));
		Files.createDirectories(Paths.get(targetRepositoryPath));
		final File packageASourceFile = new File(sourceRepositoryDir, TestUtils.A1_X64_FILENAME);
		final File packageATargetFile = new File(targetRepositoryDir, TestUtils.A2_X64_FILENAME);
		final String packageA1TargetFile = targetRepositoryDir + File.separator + TestUtils.A1_X64_FILENAME;

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), sourceRepositoryDir);
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), targetRepositoryDir);

		TestUtils.assertFileExists(packageASourceFile.getAbsolutePath());
		TestUtils.assertFileExists(packageATargetFile.getAbsolutePath());
		TestUtils.assertFileDoesNotExist(packageA1TargetFile);

		targetRepo.addPackages(sourceRepo);
		TestUtils.assertFileDoesNotExist(packageA1TargetFile);
	}

	@Test
	public void testInheritedRepository() throws Exception {
		final String sourceRepositoryPath = "target/repositories/RPMRepositoryTest.testInheritedRepository/source";
		final String targetRepositoryPath = "target/repositories/RPMRepositoryTest.testInheritedRepository/target";

		final File sourceRepositoryDir = new File(sourceRepositoryPath);
		final File targetRepositoryDir = new File(targetRepositoryPath);
		Files.createDirectories(Paths.get(sourceRepositoryPath));
		Files.createDirectories(Paths.get(targetRepositoryPath));

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), new File(targetRepositoryDir, "amd64"));
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), new File(sourceRepositoryDir, "amd64"));

		Repository sourceRepo = new RPMRepository(Paths.get(sourceRepositoryPath));
		Repository targetRepo = new RPMRepository(Paths.get(targetRepositoryPath), Util.newSortedSet(sourceRepo));

		final String packageA2TargetPath = targetRepositoryDir + File.separator + "amd64" + File.separator
				+ TestUtils.A2_X64_FILENAME;
		TestUtils.assertFileDoesNotExist(packageA2TargetPath);

		final GPGInfo gpginfo = TestUtils.generateGPGInfo();
		targetRepo.index(gpginfo);
		TestUtils.assertFileExists(packageA2TargetPath);
	}

	@Test
	public void testClone() throws Exception {
		final String sourceRepositoryPath = "target/repositories/RPMRepositoryTest.testClone/source";
		final String targetRepositoryPath = "target/repositories/RPMRepositoryTest.testClone/target";
		final GPGInfo gpginfo = TestUtils.generateGPGInfo();

		final File sourceRepositoryDir = new File(sourceRepositoryPath);
		final File targetRepositoryDir = new File(targetRepositoryPath);
		Files.createDirectories(Paths.get(sourceRepositoryPath));
		Files.createDirectories(Paths.get(targetRepositoryPath));

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), targetRepositoryDir);
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), sourceRepositoryDir);
		FileUtils.copyFileToDirectory(TestUtils.A3_X64_PATH.toFile(), sourceRepositoryDir);

		Repository sourceRepo = new RPMRepository(Paths.get(sourceRepositoryPath));
		Repository targetRepo = new RPMRepository(Paths.get(targetRepositoryPath));
		sourceRepo.index(gpginfo);
		targetRepo.index(gpginfo);

		final String packageA1TargetPath = targetRepositoryDir + File.separator + TestUtils.A1_X64_FILENAME;
		final String packageA2TargetPath = targetRepositoryDir + File.separator + TestUtils.A2_X64_FILENAME;
		final String packageA3TargetPath = targetRepositoryDir + File.separator + TestUtils.A3_X64_FILENAME;
		TestUtils.assertFileExists(packageA1TargetPath);
		TestUtils.assertFileDoesNotExist(packageA2TargetPath);
		TestUtils.assertFileDoesNotExist(packageA3TargetPath);

		sourceRepo.cloneInto(Paths.get(targetRepositoryPath));
		targetRepo.index(gpginfo);

		TestUtils.assertFileDoesNotExist(packageA1TargetPath);
		TestUtils.assertFileExists(packageA2TargetPath);
		TestUtils.assertFileExists(packageA3TargetPath);
	}
}
