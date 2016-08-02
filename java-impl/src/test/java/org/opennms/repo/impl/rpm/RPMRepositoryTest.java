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
        final File jrrd1File = new File(outputPath.toFile(), TestUtils.JRRD1_FILENAME);
        final File jrrd2File = new File(outputPath.toFile(), TestUtils.JRRD2_FILENAME);
        final File jrrd3File = new File(outputPath.toFile(), TestUtils.JRRD3_FILENAME);

        repo.addPackages(RPMUtils.getPackage(TestUtils.JRRD1_PATH.toFile()), RPMUtils.getPackage(TestUtils.JRRD2_PATH.toFile()), RPMUtils.getPackage(TestUtils.JRRD3_PATH.toFile()));
        repo.index(m_gpginfo);

        TestUtils.assertFileExists(repositoryPath + "/drpms/" + RPMUtils.getDeltaFileName(jrrd1File, jrrd2File));
        TestUtils.assertFileExists(jrrd1File.getAbsolutePath());
        TestUtils.assertFileExists(jrrd2File.getAbsolutePath());
        TestUtils.assertFileExists(jrrd3File.getAbsolutePath());
    }

    @Test
    public void testCreateRepositoryWithRPMs() throws Exception {
        final String repositoryPath = "target/repositories/RPMRepositoryTest.testCreateRepositoryWithRPMs";
        Repository repo = new RPMRepository(Paths.get(repositoryPath));
        assertFalse(repo.isValid());

        final File repositoryDir = new File(repositoryPath);
        Files.createDirectories(Paths.get(repositoryPath));
        final File jrrd1File = new File(repositoryDir, TestUtils.JRRD1_FILENAME);
        final File jrrd2File = new File(repositoryDir, TestUtils.JRRD2_FILENAME);
        final File jrrd3File = new File(repositoryDir, TestUtils.JRRD3_FILENAME);

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), repositoryDir);
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), repositoryDir);
        FileUtils.copyFileToDirectory(TestUtils.JRRD3_PATH.toFile(), repositoryDir);

        TestUtils.assertFileExists(jrrd1File.getPath());
        TestUtils.assertFileExists(jrrd2File.getPath());
        TestUtils.assertFileExists(jrrd3File.getPath());

        final GPGInfo gpginfo = TestUtils.generateGPGInfo();
        repo.index(gpginfo);

        TestUtils.assertFileExists(repositoryPath + "/repodata");
        TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml");
        TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.asc");
        TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.key");
        TestUtils.assertFileExists(repositoryPath + "/drpms/" + RPMUtils.getDeltaFileName(jrrd1File, jrrd2File));
        TestUtils.assertFileExists(repositoryPath + "/drpms/" + RPMUtils.getDeltaFileName(jrrd2File, jrrd3File));

        final List<String> lines = new ArrayList<>();
        Files.walk(Paths.get(repositoryPath).resolve("repodata")).forEach(path -> {
            if (path.toString().contains("-filelists.xml")) {
                try (final FileInputStream fis = new FileInputStream(path.toFile());
                        final GZIPInputStream gis = new GZIPInputStream(fis);
                        final InputStreamReader isr = new InputStreamReader(gis)) {
                    lines.addAll(IOUtils.readLines(gis, Charset.defaultCharset()));
                } catch (final IOException e) {
                    LOG.debug("faild to read from {}", path, e);
                };
            }
        });

        final Pattern packagesPattern = Pattern.compile(".*packages=\"(\\d+)\".*");
        final Pattern versionPattern = Pattern.compile("\\s*<version epoch=\"(\\d+)\" ver=\"([^\"]*)\" rel=\"([^\\\"]*)\"/>\\s*");
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
                //LOG.debug("Does not match: {}", line);
            }
        }
        
        assertEquals("There should be 3 packages in the file list.", 3, packages);
        final Iterator<Version> it = versions.iterator();
        
        assertTrue(it.hasNext());
        Version v = it.next();
        assertEquals(new RPMVersion(0, "1.1.0", "1"), v);
        
        assertTrue(it.hasNext());
        v = it.next();
        assertEquals(new RPMVersion(0, "1.1.0", "2.el7.centos"), v);
        
        assertTrue(it.hasNext());
        v = it.next();
        assertEquals(new RPMVersion(0, "1.1.0", "3.el7.centos"), v);
    }

    @Test
    public void testCreateRepositoryNoUpdates() throws Exception {
        final String repositoryPath = "target/repositories/RPMRepositoryTest.testCreateRepositoryNoUpdates";
        Repository repo = new RPMRepository(Paths.get(repositoryPath));
        assertFalse(repo.isValid());

        final File repositoryDir = new File(repositoryPath);
        Files.createDirectories(Paths.get(repositoryPath));
        final File jrrd1File = new File(repositoryDir, TestUtils.JRRD1_FILENAME);
        final File jrrd2File = new File(repositoryDir, TestUtils.JRRD2_FILENAME);
        final File jrrd3File = new File(repositoryDir, TestUtils.JRRD3_FILENAME);

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), repositoryDir);
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), repositoryDir);
        FileUtils.copyFileToDirectory(TestUtils.JRRD3_PATH.toFile(), repositoryDir);

        TestUtils.assertFileExists(jrrd1File.getPath());
        TestUtils.assertFileExists(jrrd2File.getPath());
        TestUtils.assertFileExists(jrrd3File.getPath());

        final GPGInfo gpginfo = TestUtils.generateGPGInfo();
        repo.index(gpginfo);

        TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml");
        TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.asc");
        TestUtils.assertFileExists(repositoryPath + "/repodata/repomd.xml.key");
        TestUtils.assertFileExists(repositoryPath + "/drpms/" + RPMUtils.getDeltaFileName(jrrd1File, jrrd2File));
        TestUtils.assertFileExists(repositoryPath + "/drpms/" + RPMUtils.getDeltaFileName(jrrd2File, jrrd3File));

        final Path repodata = Paths.get(repositoryPath).resolve("repodata");
        final Path drpms = Paths.get(repositoryPath).resolve("drpms");
        
        final Map<Path, FileTime> fileTimes = new HashMap<>();
        final Path[] repositoryPaths = new Path[] {
                repodata.resolve("repomd.xml"),
                repodata.resolve("repomd.xml.asc"),
                repodata.resolve("repomd.xml.key"),
                drpms.resolve(RPMUtils.getDeltaFileName(jrrd1File, jrrd2File)),
                drpms.resolve(RPMUtils.getDeltaFileName(jrrd2File, jrrd3File))
        };

        for (final Path p : repositoryPaths) {
            fileTimes.put(p, Util.getFileTime(p));
        }

        repo.index(gpginfo);
    
        for (final Path p : repositoryPaths) {
            assertEquals(p + " time should not have changed after a reindex", fileTimes.get(p), Util.getFileTime(p));
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
        final File jrrd1TargetFile = new File(new File(targetRepositoryDir, "amd64"), TestUtils.JRRD1_FILENAME);
        final File jrrd2SourceFile = new File(new File(sourceRepositoryDir, "amd64"), TestUtils.JRRD2_FILENAME);
        final String jrrd2TargetFile = targetRepositoryDir + File.separator + "amd64" + File.separator + TestUtils.JRRD2_FILENAME;

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), new File(targetRepositoryDir, "amd64"));
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), new File(sourceRepositoryDir, "amd64"));

        TestUtils.assertFileExists(jrrd1TargetFile.getAbsolutePath());
        TestUtils.assertFileExists(jrrd2SourceFile.getAbsolutePath());
        TestUtils.assertFileDoesNotExist(jrrd2TargetFile);

        targetRepo.addPackages(sourceRepo);
        TestUtils.assertFileExists(jrrd2TargetFile);
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
        final File jrrdSourceFile = new File(sourceRepositoryDir, TestUtils.JRRD1_FILENAME);
        final File jrrdTargetFile = new File(targetRepositoryDir, TestUtils.JRRD2_FILENAME);
        final String jrrd1TargetFile = targetRepositoryDir + File.separator + TestUtils.JRRD1_FILENAME;

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), sourceRepositoryDir);
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), targetRepositoryDir);

        TestUtils.assertFileExists(jrrdSourceFile.getAbsolutePath());
        TestUtils.assertFileExists(jrrdTargetFile.getAbsolutePath());
        TestUtils.assertFileDoesNotExist(jrrd1TargetFile);

        targetRepo.addPackages(sourceRepo);
        TestUtils.assertFileDoesNotExist(jrrd1TargetFile);
    }

    @Test
    public void testInheritedRepository() throws Exception {
        final String sourceRepositoryPath = "target/repositories/RPMRepositoryTest.testInheritedRepository/source";
        final String targetRepositoryPath = "target/repositories/RPMRepositoryTest.testInheritedRepository/target";

        final File sourceRepositoryDir = new File(sourceRepositoryPath);
        final File targetRepositoryDir = new File(targetRepositoryPath);
        Files.createDirectories(Paths.get(sourceRepositoryPath));
        Files.createDirectories(Paths.get(targetRepositoryPath));

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), new File(targetRepositoryDir, "amd64"));
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), new File(sourceRepositoryDir, "amd64"));

        Repository sourceRepo = new RPMRepository(Paths.get(sourceRepositoryPath));
        Repository targetRepo = new RPMRepository(Paths.get(targetRepositoryPath), sourceRepo);

        final String jrrd2TargetPath = targetRepositoryDir + File.separator + "amd64" + File.separator + TestUtils.JRRD2_FILENAME;
        TestUtils.assertFileDoesNotExist(jrrd2TargetPath);
        
        final GPGInfo gpginfo = TestUtils.generateGPGInfo();
        targetRepo.index(gpginfo);
        TestUtils.assertFileExists(jrrd2TargetPath);
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

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), targetRepositoryDir);
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), sourceRepositoryDir);
        FileUtils.copyFileToDirectory(TestUtils.JRRD3_PATH.toFile(), sourceRepositoryDir);

        Repository sourceRepo = new RPMRepository(Paths.get(sourceRepositoryPath));
        Repository targetRepo = new RPMRepository(Paths.get(targetRepositoryPath));
        sourceRepo.index(gpginfo);
        targetRepo.index(gpginfo);

        final String jrrd1TargetPath = targetRepositoryDir + File.separator + TestUtils.JRRD1_FILENAME;
        final String jrrd2TargetPath = targetRepositoryDir + File.separator + TestUtils.JRRD2_FILENAME;
        final String jrrd3TargetPath = targetRepositoryDir + File.separator + TestUtils.JRRD3_FILENAME;
        TestUtils.assertFileExists(jrrd1TargetPath);
        TestUtils.assertFileDoesNotExist(jrrd2TargetPath);
        TestUtils.assertFileDoesNotExist(jrrd3TargetPath);

        sourceRepo.cloneInto(Paths.get(targetRepositoryPath));
        targetRepo.index(gpginfo);

        TestUtils.assertFileDoesNotExist(jrrd1TargetPath);
        TestUtils.assertFileExists(jrrd2TargetPath);
        TestUtils.assertFileExists(jrrd3TargetPath);
    }
}
