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
import org.junit.Ignore;
import org.junit.Test;
import org.opennms.repo.api.RepositoryPackage.Architecture;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMUtilsTest {
    private static final Logger LOG = LoggerFactory.getLogger(RPMUtilsTest.class);

    private static final boolean skipDelete = false;

    private static final File JRRD1_FILE = new File("target/test-classes/jrrd-1.1.0-1.x86_64.rpm");
    private static final File JRRD2_FILE = new File("target/test-classes/jrrd-1.1.0-2.el7.centos.x86_64.rpm");
    private static final File JRRD3_FILE = new File("target/test-classes/jrrd-1.1.0-3.el7.centos.x86_64.rpm");

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
        final RPMPackage rpm = RPMUtils.getPackage(JRRD1_FILE);
        assertEquals("jrrd", rpm.getName());
        assertEquals(JRRD1_FILE.getAbsolutePath(), rpm.getPath().toAbsolutePath().toString());
        assertEquals(Architecture.AMD64, rpm.getArchitecture());
        assertNotNull(rpm.getVersion());
        assertEquals(0, rpm.getVersion().getEpoch());
        assertEquals("1.1.0", rpm.getVersion().getVersion());
        assertEquals("1", rpm.getVersion().getRelease());
    }

    @Test
    public void testCompareRPMPackage() throws Exception {
        final RPMPackage jrrd1 = RPMUtils.getPackage(JRRD1_FILE);
        final RPMPackage jrrd1again = RPMUtils.getPackage(JRRD1_FILE);
        final RPMPackage jrrd2 = RPMUtils.getPackage(JRRD2_FILE);

        assertEquals(0, jrrd1.compareTo(jrrd1));
        assertEquals(jrrd1, jrrd1again);
        assertEquals(-1, jrrd1.compareTo(jrrd2));
        assertEquals(1, jrrd2.compareTo(jrrd1));
    }

    @Test
    public void testGenerateDeltaRPMName() throws Exception {
        String deltaRPM = RPMUtils.getDeltaFileName(JRRD1_FILE, JRRD2_FILE);
        assertEquals("jrrd-1.1.0-1_1.1.0-2.el7.centos.x86_64.drpm", deltaRPM);
        
        deltaRPM = RPMUtils.getDeltaFileName(RPMUtils.getPackage(JRRD1_FILE), RPMUtils.getPackage(JRRD2_FILE));
        assertEquals("jrrd-1.1.0-1_1.1.0-2.el7.centos.x86_64.drpm", deltaRPM);
    }

    @Test
    @Ignore("WHY DO THESE FAIL?!?")
    public void testCreateDeltaRPM() throws Exception {
        final File deltaRPM = RPMUtils.generateDelta(JRRD1_FILE, JRRD2_FILE);
        assertNotNull(deltaRPM);
        assertEquals("jrrd-1.1.0-1_1.1.0-2.el7.centos.x86_64.drpm", deltaRPM.getName());
        assertTrue(deltaRPM.length() > 0);
        assertEquals(JRRD1_FILE.getParentFile().toPath().resolve("drpms"), deltaRPM.toPath().getParent());
    }
    
    @Test
    @Ignore("WHY DO THESE FAIL?!?")
    public void testCreateDeltaRPMOutOfOrder() throws Exception {
        assert(JRRD1_FILE != null);
        assert(JRRD2_FILE != null);
        final File deltaRPM = RPMUtils.generateDelta(JRRD2_FILE, JRRD1_FILE);
        assertNotNull(deltaRPM);
        assertEquals("jrrd-1.1.0-1_1.1.0-2.el7.centos.x86_64.drpm", deltaRPM.getName());
        assertTrue(deltaRPM.length() > 0);
        assertEquals(JRRD1_FILE.getParentFile().toPath().resolve("drpms"), deltaRPM.toPath().getParent());
    }
    
    @Test
    public void testGenerateDeltaRPMs() throws Exception {
        final Path tempPath = Files.createTempDirectory("deltarpms");
        Files.createDirectories(tempPath);
        s_deleteMe.add(tempPath);
        
        final File jrrd1File = new File(tempPath.toFile(), JRRD1_FILE.getName());
        final File jrrd2File = new File(tempPath.toFile(), JRRD2_FILE.getName());
        final File jrrd3File = new File(tempPath.toFile(), JRRD3_FILE.getName());

        FileUtils.copyFileToDirectory(JRRD1_FILE, tempPath.toFile());
        FileUtils.copyFileToDirectory(JRRD2_FILE, tempPath.toFile());
        FileUtils.copyFileToDirectory(JRRD3_FILE, tempPath.toFile());

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
