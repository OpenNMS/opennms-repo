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
import java.util.SortedSet;
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

		for (int i = 0; i < 16; i++) {
			assertEquals(expected[i], versions.get(i));
		}
	}

	@Test
	public void testGetDeltasForPackages() throws Exception {
		final SortedSet<RPMPackage> packages = RPMUtils.getPackages(Paths.get("target/test-classes"));
		assertEquals(16, packages.size());
		final List<DeltaRPM> deltas = new ArrayList<>(RPMUtils.getDeltas(packages));
		assertEquals(12, deltas.size());

		assertEquals("jicmp-1.4.1-1_2.0.0-0.5.i386.drpm", deltas.get(0).getFileName());
		assertEquals("jicmp-1.4.1-1_2.0.0-0.5.x86_64.drpm", deltas.get(1).getFileName());
		assertEquals("jicmp-1.4.5-2_2.0.0-0.5.i386.drpm", deltas.get(2).getFileName());
		assertEquals("jicmp-1.4.5-2_2.0.0-0.5.x86_64.drpm", deltas.get(3).getFileName());
		assertEquals("jicmp-2.0.0-0.1_2.0.0-0.5.i386.drpm", deltas.get(4).getFileName());
		assertEquals("jicmp-2.0.0-0.1_2.0.0-0.5.x86_64.drpm", deltas.get(5).getFileName());
		assertEquals("jicmp6-1.2.1-1_2.0.0-0.5.i386.drpm", deltas.get(6).getFileName());
		assertEquals("jicmp6-1.2.1-1_2.0.0-0.5.x86_64.drpm", deltas.get(7).getFileName());
		assertEquals("jicmp6-1.2.4-1_2.0.0-0.5.i386.drpm", deltas.get(8).getFileName());
		assertEquals("jicmp6-1.2.4-1_2.0.0-0.5.x86_64.drpm", deltas.get(9).getFileName());
		assertEquals("jicmp6-2.0.0-0.2_2.0.0-0.5.i386.drpm", deltas.get(10).getFileName());
		assertEquals("jicmp6-2.0.0-0.2_2.0.0-0.5.x86_64.drpm", deltas.get(11).getFileName());
	}

	@Test
	public void testGenerateDeltaRPMName() throws Exception {
		DeltaRPM drpm = new DeltaRPM(RPMUtils.getPackage(TestUtils.A1_I386_PATH.toFile()), RPMUtils.getPackage(TestUtils.A2_I386_PATH.toFile()));
		assertEquals("jicmp-1.4.1-1_1.4.5-2.i386.drpm", drpm.getFileName());
	}

	@Test
	public void testGenerateDeltaRPMNameOutOfOrder() throws Exception {
		DeltaRPM drpm = new DeltaRPM(RPMUtils.getPackage(TestUtils.A2_I386_PATH.toFile()), RPMUtils.getPackage(TestUtils.A1_I386_PATH.toFile()));
		assertEquals("jicmp-1.4.1-1_1.4.5-2.i386.drpm", drpm.getFileName());
	}

	@Test
	public void testCreateDeltaRPM() throws Exception {
		final File deltaRPM = RPMUtils.generateDelta(TestUtils.A1_I386_PATH.toFile(), TestUtils.A2_I386_PATH.toFile());
		assertNotNull(deltaRPM);
		assertEquals("jicmp-1.4.1-1_1.4.5-2.i386.drpm", deltaRPM.getName());
		assertTrue(deltaRPM.length() > 0);
		assertEquals(TestUtils.A1_I386_PATH.toFile().getParentFile().toPath().normalize().toAbsolutePath().resolve("drpms"), deltaRPM.toPath().getParent());
	}

	@Test
	public void testCreateDeltaRPMOutOfOrder() throws Exception {
		assert (TestUtils.A1_I386_PATH.toFile() != null);
		assert (TestUtils.A3_I386_PATH.toFile() != null);
		final File deltaRPM = RPMUtils.generateDelta(TestUtils.A3_I386_PATH.toFile(), TestUtils.A1_I386_PATH.toFile());
		assertNotNull(deltaRPM);
		assertEquals("jicmp-1.4.1-1_2.0.0-0.1.i386.drpm", deltaRPM.getName());
		assertTrue(deltaRPM.length() > 0);
		assertEquals(TestUtils.A1_I386_PATH.toFile().getParentFile().toPath().normalize().toAbsolutePath().resolve("drpms"), deltaRPM.toPath().getParent());
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

		final RPMPackage packageA1 = RPMUtils.getPackage(packageA1File);
		final RPMPackage packageA2 = RPMUtils.getPackage(packageA2File);
		final RPMPackage packageA3 = RPMUtils.getPackage(packageA3File);

		final DeltaRPM drpm12 = new DeltaRPM(packageA1, packageA2);
		final DeltaRPM drpm13 = new DeltaRPM(packageA1, packageA3);
		final DeltaRPM drpm23 = new DeltaRPM(packageA2, packageA3);

		final Path drpm12Path = drpm12.getFilePath(tempPath.resolve("drpms"));
		assertFalse(drpm12Path + " should not exist", drpm12Path.toFile().exists());

		final Path drpm23Path = drpm23.getFilePath(tempPath.resolve("drpms"));
		assertTrue(drpm23Path + " should exist", drpm23Path.toFile().exists());

		final Path drpm13Path = drpm13.getFilePath(tempPath.resolve("drpms"));
		assertTrue(drpm13Path + " should exist", drpm13Path.toFile().exists());
	}
}
