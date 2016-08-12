package org.opennms.repo.impl.rpm;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.opennms.repo.api.RepositoryPackage.Architecture;
import org.opennms.repo.api.Version;
import org.opennms.repo.impl.TestUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMUtilsTest {
	private static final Logger LOG = LoggerFactory.getLogger(RPMUtilsTest.class);

	private static final boolean skipDelete = false;

	private static final Set<Path> s_deleteMe = new HashSet<>();

	@Before
	@After
	public void cleanUpDRPMS() {
		if (skipDelete) {
			return;
		}
		s_deleteMe.add(Paths.get("target/test-classes/drpms"));
		for (final Path p : s_deleteMe) {
			try {
				final File f = p.toFile();
				if (f.isDirectory()) {
					FileUtils.deleteDirectory(f);
				} else {
					f.delete();
				}
			} catch (final Exception e) {
				LOG.warn("Failed to delete drpms directory.");
			}
		}
		s_deleteMe.clear();
	}

	@Test
	public void testReadRPMPackage() throws Exception {
		final RPMPackage rpm = RPMUtils.getPackage(TestUtils.A1_I386_PATH.toFile());
		assertEquals("jicmp", rpm.getName());
		assertEquals(TestUtils.A1_I386_PATH.toFile().getAbsolutePath(), rpm.getPath().toAbsolutePath().toString());
		assertEquals(Architecture.I386, rpm.getArchitecture());
		assertNotNull(rpm.getVersion());
		assertEquals(0, rpm.getVersion().getEpoch());
		assertEquals("1.4.1", rpm.getVersion().getVersion());
		assertEquals("1", rpm.getVersion().getRelease());
	}

	@Test
	public void testCompareRPMPackage() throws Exception {
		final RPMPackage packageA1 = RPMUtils.getPackage(TestUtils.A1_I386_PATH.toFile());
		final RPMPackage packageA1again = RPMUtils.getPackage(TestUtils.A1_I386_PATH.toFile());
		final RPMPackage packageA1x64 = RPMUtils.getPackage(TestUtils.A1_X64_PATH.toFile());
		final RPMPackage packageA2 = RPMUtils.getPackage(TestUtils.A2_I386_PATH.toFile());

		assertEquals(0, packageA1.compareTo(packageA1));
		assertEquals(packageA1, packageA1again);
		assertEquals(-1, packageA1.compareTo(packageA1x64));
		assertEquals(-1, packageA1.compareTo(packageA2));
		assertEquals(1, packageA2.compareTo(packageA1));
	}

	@Test
	public void testGetPackages() throws Exception {
		final List<RPMPackage> packages = new ArrayList<>(RPMUtils.getPackages(Paths.get("target/test-classes")));
		assertEquals(16, packages.size());
		assertEquals(Architecture.I386, packages.get(0).getArchitecture());
		assertEquals(Architecture.AMD64, packages.get(1).getArchitecture());

		final List<Version> versions = packages.stream().map(pack -> {
			return pack.getVersion();
		}).collect(Collectors.toList());

		LOG.debug("versions = {}", versions);

		final Version[] expected = {
				new RPMVersion("1.4.1", "1"), // i386
				new RPMVersion("1.4.1", "1"), // x64
				new RPMVersion("1.4.5", "2"), // i386
				new RPMVersion("1.4.5", "2"), // x64
				new RPMVersion("2.0.0", "0.1"), // i386
				new RPMVersion("2.0.0", "0.1"), // x64
				new RPMVersion("2.0.0", "0.5"), // i386
				new RPMVersion("2.0.0", "0.5"), // x64
				new RPMVersion("1.2.1", "1"), // i386
				new RPMVersion("1.2.1", "1"), // x64
				new RPMVersion("1.2.4", "1"), // i386
				new RPMVersion("1.2.4", "1"), // x64
				new RPMVersion("2.0.0", "0.2"), // i386
				new RPMVersion("2.0.0", "0.2"), // x64
				new RPMVersion("2.0.0", "0.5"), // i386
				new RPMVersion("2.0.0", "0.5") // x64
		};
		
		for (int i=0; i < 16; i++) {
			assertEquals(expected[i], versions.get(i));
		}
	}

	@Test
	public void testGenerateDeltaRPMName() throws Exception {
		String deltaRPM = RPMUtils.getDeltaFileName(TestUtils.A1_I386_PATH.toFile(), TestUtils.A2_I386_PATH.toFile());
		assertEquals("jicmp-1.4.1-1_1.4.5-2.i386.drpm", deltaRPM);

		deltaRPM = RPMUtils.getDeltaFileName(RPMUtils.getPackage(TestUtils.A1_I386_PATH.toFile()), RPMUtils.getPackage(TestUtils.A2_I386_PATH.toFile()));
		assertEquals("jicmp-1.4.1-1_1.4.5-2.i386.drpm", deltaRPM);
	}

	@Test
	public void testGenerateDeltaRPMNameOutOfOrder() throws Exception {
		String deltaRPM = RPMUtils.getDeltaFileName(TestUtils.A2_I386_PATH.toFile(), TestUtils.A1_I386_PATH.toFile());
		assertEquals("jicmp-1.4.1-1_1.4.5-2.i386.drpm", deltaRPM);

		deltaRPM = RPMUtils.getDeltaFileName(RPMUtils.getPackage(TestUtils.A2_I386_PATH.toFile()), RPMUtils.getPackage(TestUtils.A1_I386_PATH.toFile()));
		assertEquals("jicmp-1.4.1-1_1.4.5-2.i386.drpm", deltaRPM);
	}

	@Test
	public void testCreateDeltaRPM() throws Exception {
		final File deltaRPM = RPMUtils.generateDelta(TestUtils.A1_I386_PATH.toFile(), TestUtils.A2_I386_PATH.toFile());
		assertNotNull(deltaRPM);
		assertEquals("jicmp-1.4.1-1_1.4.5-2.i386.drpm", deltaRPM.getName());
		assertTrue(deltaRPM.length() > 0);
		assertEquals(
				TestUtils.A1_I386_PATH.toFile().getParentFile().toPath().normalize().toAbsolutePath().resolve("drpms"),
				deltaRPM.toPath().getParent());
	}

	@Test
	public void testCreateDeltaRPMOutOfOrder() throws Exception {
		assert (TestUtils.A1_I386_PATH.toFile() != null);
		assert (TestUtils.A3_I386_PATH.toFile() != null);
		final File deltaRPM = RPMUtils.generateDelta(TestUtils.A3_I386_PATH.toFile(), TestUtils.A1_I386_PATH.toFile());
		assertNotNull(deltaRPM);
		assertEquals("jicmp-1.4.1-1_2.0.0-0.1.i386.drpm", deltaRPM.getName());
		assertTrue(deltaRPM.length() > 0);
		assertEquals(
				TestUtils.A1_I386_PATH.toFile().getParentFile().toPath().normalize().toAbsolutePath().resolve("drpms"),
				deltaRPM.toPath().getParent());
	}

	@Test
	public void testGenerateDeltaRPMs() throws Exception {
		final Path tempPath = Files.createTempDirectory("deltarpms");
		Files.createDirectories(tempPath);
		s_deleteMe.add(tempPath);

		final File packageA1File = new File(tempPath.toFile(), TestUtils.A1_I386_FILENAME);
		final File packageA2File = new File(tempPath.toFile(), TestUtils.A2_I386_FILENAME);
		final File packageA3File = new File(tempPath.toFile(), TestUtils.A3_I386_FILENAME);

		FileUtils.copyFileToDirectory(TestUtils.A1_I386_PATH.toFile(), tempPath.toFile());
		FileUtils.copyFileToDirectory(TestUtils.A2_I386_PATH.toFile(), tempPath.toFile());
		FileUtils.copyFileToDirectory(TestUtils.A3_I386_PATH.toFile(), tempPath.toFile());

		assertTrue(packageA1File.exists());
		assertTrue(packageA2File.exists());
		assertTrue(packageA3File.exists());

		RPMUtils.generateDeltas(tempPath.toFile());

		final String delta12Name = RPMUtils.getDeltaFileName(packageA1File, packageA2File);
		final Path drpm12Path = tempPath.resolve("drpms").resolve(delta12Name);
		assertTrue(drpm12Path + " should exist", drpm12Path.toFile().exists());

		final String delta23Name = RPMUtils.getDeltaFileName(packageA2File, packageA3File);
		final Path drpm23Path = tempPath.resolve("drpms").resolve(delta23Name);
		assertTrue(drpm23Path + " should exist", drpm23Path.toFile().exists());

		final String delta13Name = RPMUtils.getDeltaFileName(packageA1File, packageA3File);
		final Path drpm13Path = tempPath.resolve("drpms").resolve(delta13Name);
		assertFalse(drpm13Path + " should NOT exist", drpm13Path.toFile().exists());
	}
}
