package org.opennms.repo.impl.rpm;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashSet;
import java.util.Set;

import org.apache.commons.io.FileUtils;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.opennms.repo.api.RepositoryPackage.Architecture;
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
        final RPMPackage rpm = RPMUtils.getPackage(TestUtils.JRRD1_PATH.toFile());
        assertEquals("jrrd", rpm.getName());
        assertEquals(TestUtils.JRRD1_PATH.toFile().getAbsolutePath(), rpm.getPath().toAbsolutePath().toString());
        assertEquals(Architecture.AMD64, rpm.getArchitecture());
        assertNotNull(rpm.getVersion());
        assertEquals(0, rpm.getVersion().getEpoch());
        assertEquals("1.1.0", rpm.getVersion().getVersion());
        assertEquals("1", rpm.getVersion().getRelease());
    }

    @Test
    public void testCompareRPMPackage() throws Exception {
        final RPMPackage jrrd1 = RPMUtils.getPackage(TestUtils.JRRD1_PATH.toFile());
        final RPMPackage jrrd1again = RPMUtils.getPackage(TestUtils.JRRD1_PATH.toFile());
        final RPMPackage jrrd2 = RPMUtils.getPackage(TestUtils.JRRD2_PATH.toFile());

        assertEquals(0, jrrd1.compareTo(jrrd1));
        assertEquals(jrrd1, jrrd1again);
        assertEquals(-1, jrrd1.compareTo(jrrd2));
        assertEquals(1, jrrd2.compareTo(jrrd1));
    }

    @Test
    public void testGenerateDeltaRPMName() throws Exception {
        String deltaRPM = RPMUtils.getDeltaFileName(TestUtils.JRRD1_PATH.toFile(), TestUtils.JRRD2_PATH.toFile());
        assertEquals("jrrd-1.1.0-1_1.1.0-2.el7.centos.x86_64.drpm", deltaRPM);
        
        deltaRPM = RPMUtils.getDeltaFileName(RPMUtils.getPackage(TestUtils.JRRD1_PATH.toFile()), RPMUtils.getPackage(TestUtils.JRRD2_PATH.toFile()));
        assertEquals("jrrd-1.1.0-1_1.1.0-2.el7.centos.x86_64.drpm", deltaRPM);
    }

    @Test
    public void testCreateDeltaRPM() throws Exception {
        final File deltaRPM = RPMUtils.generateDelta(TestUtils.JRRD1_PATH.toFile(), TestUtils.JRRD2_PATH.toFile());
        assertNotNull(deltaRPM);
        assertEquals("jrrd-1.1.0-1_1.1.0-2.el7.centos.x86_64.drpm", deltaRPM.getName());
        assertTrue(deltaRPM.length() > 0);
        assertEquals(TestUtils.JRRD1_PATH.toFile().getParentFile().toPath().normalize().toAbsolutePath().resolve("drpms"), deltaRPM.toPath().getParent());
    }
    
    @Test
    public void testCreateDeltaRPMOutOfOrder() throws Exception {
        assert(TestUtils.JRRD1_PATH.toFile() != null);
        assert(TestUtils.JRRD2_PATH.toFile() != null);
        final File deltaRPM = RPMUtils.generateDelta(TestUtils.JRRD2_PATH.toFile(), TestUtils.JRRD1_PATH.toFile());
        assertNotNull(deltaRPM);
        assertEquals("jrrd-1.1.0-1_1.1.0-2.el7.centos.x86_64.drpm", deltaRPM.getName());
        assertTrue(deltaRPM.length() > 0);
        assertEquals(TestUtils.JRRD1_PATH.toFile().getParentFile().toPath().normalize().toAbsolutePath().resolve("drpms"), deltaRPM.toPath().getParent());
    }
    
    @Test
    public void testGenerateDeltaRPMs() throws Exception {
        final Path tempPath = Files.createTempDirectory("deltarpms");
        Files.createDirectories(tempPath);
        s_deleteMe.add(tempPath);
        
        final File jrrd1File = new File(tempPath.toFile(), TestUtils.JRRD1_FILENAME);
        final File jrrd2File = new File(tempPath.toFile(), TestUtils.JRRD2_FILENAME);
        final File jrrd3File = new File(tempPath.toFile(), TestUtils.JRRD3_FILENAME);

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), tempPath.toFile());
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), tempPath.toFile());
        FileUtils.copyFileToDirectory(TestUtils.JRRD3_PATH.toFile(), tempPath.toFile());

        assertTrue(jrrd1File.exists());
        assertTrue(jrrd2File.exists());
        assertTrue(jrrd3File.exists());
        
        RPMUtils.generateDeltas(tempPath.toFile());
        
        final String delta12Name = RPMUtils.getDeltaFileName(jrrd1File, jrrd2File);
        final Path drpm12Path = tempPath.resolve("drpms").resolve(delta12Name);
        assertTrue(drpm12Path + " should exist", drpm12Path.toFile().exists());
        
        final String delta23Name = RPMUtils.getDeltaFileName(jrrd2File, jrrd3File);
        final Path drpm23Path = tempPath.resolve("drpms").resolve(delta23Name);
        assertTrue(drpm23Path + " should exist", drpm23Path.toFile().exists());
        
        final String delta13Name = RPMUtils.getDeltaFileName(jrrd1File, jrrd3File);
        final Path drpm13Path = tempPath.resolve("drpms").resolve(delta13Name);
        assertFalse(drpm13Path + " should NOT exist", drpm13Path.toFile().exists());
    }
}
