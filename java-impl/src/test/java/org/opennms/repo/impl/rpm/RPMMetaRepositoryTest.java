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
        final File jrrd1File = new File(outputPath.toFile(), TestUtils.JRRD1_FILENAME);
        final File jrrd2File = new File(outputPath.toFile(), TestUtils.JRRD2_FILENAME);
        final File jrrd3File = new File(outputPath.toFile(), TestUtils.JRRD3_FILENAME);

        repo.addPackages(RPMUtils.getPackage(TestUtils.JRRD1_PATH), RPMUtils.getPackage(TestUtils.JRRD2_PATH), RPMUtils.getPackage(TestUtils.JRRD3_PATH));
        repo.index(m_gpginfo);

        TestUtils.assertFileExists(outputPath.resolve("..").resolve("drpms").resolve(RPMUtils.getDeltaFileName(jrrd1File, jrrd2File)).normalize().toString());
        TestUtils.assertFileExists(jrrd1File.getAbsolutePath());
        TestUtils.assertFileExists(jrrd2File.getAbsolutePath());
        TestUtils.assertFileExists(jrrd3File.getAbsolutePath());
    }

    @Test
    public void testAddRPMsToMetaSubRepository() throws Exception {
        final String repositoryPath = "target/repositories/RPMMetaRepositoryTest.testAddRPMsToMetaSubRepository";
        MetaRepository repo = new RPMMetaRepository(Paths.get(repositoryPath));
        assertFalse(repo.isValid());

        final Path outputPath = Paths.get(repositoryPath).resolve("rhel5").resolve("amd64");
        final File jrrd1File = new File(outputPath.toFile(), TestUtils.JRRD1_FILENAME);
        final File jrrd2File = new File(outputPath.toFile(), TestUtils.JRRD2_FILENAME);
        final File jrrd3File = new File(outputPath.toFile(), TestUtils.JRRD3_FILENAME);

        repo.addPackages("rhel5", RPMUtils.getPackage(TestUtils.JRRD1_PATH), RPMUtils.getPackage(TestUtils.JRRD2_PATH), RPMUtils.getPackage(TestUtils.JRRD3_PATH));
        repo.index(m_gpginfo);

        TestUtils.assertFileExists(outputPath.resolve("..").resolve("drpms").resolve(RPMUtils.getDeltaFileName(jrrd1File, jrrd2File)).normalize().toString());
        TestUtils.assertFileExists(jrrd1File.getAbsolutePath());
        TestUtils.assertFileExists(jrrd2File.getAbsolutePath());
        TestUtils.assertFileExists(jrrd3File.getAbsolutePath());
    }

    @Test
    public void testCreateRepositoryWithRPMs() throws Exception {
        final String repositoryPath = "target/repositories/RPMMetaRepositoryTest.testCreateRepositoryWithRPMs";
        Repository repo = new RPMMetaRepository(Paths.get(repositoryPath));
        assertFalse(repo.isValid());

        final Path repositoryDir = Paths.get(repositoryPath).resolve("common").resolve("amd64");
        Files.createDirectories(Paths.get(repositoryPath));
        final File repositoryFile = repositoryDir.toFile();
		final File jrrd1File = new File(repositoryFile, TestUtils.JRRD1_FILENAME);
        final File jrrd2File = new File(repositoryFile, TestUtils.JRRD2_FILENAME);
        final File jrrd3File = new File(repositoryFile, TestUtils.JRRD3_FILENAME);

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), repositoryFile);
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), repositoryFile);
        FileUtils.copyFileToDirectory(TestUtils.JRRD3_PATH.toFile(), repositoryFile);

        TestUtils.assertFileExists(jrrd1File.getPath());
        TestUtils.assertFileExists(jrrd2File.getPath());
        TestUtils.assertFileExists(jrrd3File.getPath());

        repo.index(m_gpginfo);

        TestUtils.assertFileExists(repositoryPath + "/common/repodata");
        TestUtils.assertFileExists(repositoryPath + "/common/repodata/repomd.xml");
        TestUtils.assertFileExists(repositoryPath + "/common/repodata/repomd.xml.asc");
        TestUtils.assertFileExists(repositoryPath + "/common/repodata/repomd.xml.key");
        TestUtils.assertFileExists(repositoryPath + "/common/drpms/" + RPMUtils.getDeltaFileName(jrrd1File, jrrd2File));
        TestUtils.assertFileExists(repositoryPath + "/common/drpms/" + RPMUtils.getDeltaFileName(jrrd2File, jrrd3File));

        final List<String> lines = new ArrayList<>();
        Files.walk(Paths.get(repositoryPath).resolve("common").resolve("repodata")).forEach(path -> {
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
        final String repositoryPath = "target/repositories/RPMMetaRepositoryTest.testCreateRepositoryNoUpdates";
        Repository repo = new RPMMetaRepository(Paths.get(repositoryPath));
        assertFalse(repo.isValid());

        final Path commonPath = Paths.get(repositoryPath).resolve("common");
        final Path archPath = commonPath.resolve("amd64");
        Files.createDirectories(archPath);
        Files.createDirectories(Paths.get(repositoryPath));
        final File jrrd1File = new File(archPath.toFile(), TestUtils.JRRD1_FILENAME);
        final File jrrd2File = new File(archPath.toFile(), TestUtils.JRRD2_FILENAME);
        final File jrrd3File = new File(archPath.toFile(), TestUtils.JRRD3_FILENAME);

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), archPath.toFile());
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), archPath.toFile());
        FileUtils.copyFileToDirectory(TestUtils.JRRD3_PATH.toFile(), archPath.toFile());

        TestUtils.assertFileExists(jrrd1File.getPath());
        TestUtils.assertFileExists(jrrd2File.getPath());
        TestUtils.assertFileExists(jrrd3File.getPath());

        repo.index(m_gpginfo);

        final Path repodata = commonPath.resolve("repodata");
        final Path drpms = commonPath.resolve("drpms");
        
        TestUtils.assertFileExists(repodata.resolve("repomd.xml"));
        TestUtils.assertFileExists(repodata.resolve("repomd.xml.asc"));
        TestUtils.assertFileExists(repodata.resolve("repomd.xml.key"));
        TestUtils.assertFileExists(drpms.resolve(RPMUtils.getDeltaFileName(jrrd1File, jrrd2File)));
        TestUtils.assertFileExists(drpms.resolve(RPMUtils.getDeltaFileName(jrrd2File, jrrd3File)));

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
        final File jrrd1TargetFile = new File(targetRepositoryCommon.resolve("amd64").toFile(), TestUtils.JRRD1_FILENAME);
        final File jrrd2SourceFile = new File(sourceRepositoryCommon.resolve("amd64").toFile(), TestUtils.JRRD2_FILENAME);
        final Path jrrd2TargetFile = targetRepositoryCommon.resolve("amd64").resolve(TestUtils.JRRD2_FILENAME);

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), new File(targetRepositoryCommon.toFile(), "amd64"));
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), new File(sourceRepositoryCommon.toFile(), "amd64"));

        TestUtils.assertFileExists(jrrd1TargetFile.getAbsolutePath());
        TestUtils.assertFileExists(jrrd2SourceFile.getAbsolutePath());
        TestUtils.assertFileDoesNotExist(jrrd2TargetFile);

        targetRepo.addPackages(sourceRepo);
        TestUtils.assertFileExists(jrrd2TargetFile);
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
        final File jrrd1TargetFile = new File(targetRepositoryCommon.resolve("amd64").toFile(), TestUtils.JRRD1_FILENAME);
        final File jrrd2SourceFile = new File(sourceRepositoryCommon.resolve("amd64").toFile(), TestUtils.JRRD2_FILENAME);
        final Path jrrd2TargetFile = targetRepositoryCommon.resolve("amd64").resolve(TestUtils.JRRD2_FILENAME);

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), new File(targetRepositoryCommon.toFile(), "amd64"));
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), new File(sourceRepositoryCommon.toFile(), "amd64"));

        TestUtils.assertFileExists(jrrd1TargetFile.getAbsolutePath());
        TestUtils.assertFileExists(jrrd2SourceFile.getAbsolutePath());
        TestUtils.assertFileDoesNotExist(jrrd2TargetFile);

        targetRepo.addPackages("rhel5", sourceRepo);
        TestUtils.assertFileExists(jrrd2TargetFile);
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
        final File jrrdSourceFile = new File(sourceArchPath.toFile(), TestUtils.JRRD1_FILENAME);
        final File jrrdTargetFile = new File(targetArchPath.toFile(), TestUtils.JRRD2_FILENAME);
        final String jrrd1TargetFile = targetArchPath.resolve(TestUtils.JRRD1_FILENAME).toString();

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), sourceArchPath.toFile());
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), targetArchPath.toFile());

        TestUtils.assertFileExists(jrrdSourceFile.getAbsolutePath());
        TestUtils.assertFileExists(jrrdTargetFile.getAbsolutePath());
        TestUtils.assertFileDoesNotExist(jrrd1TargetFile);

        targetRepo.addPackages(sourceRepo);
        TestUtils.assertFileDoesNotExist(jrrd1TargetFile);
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

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), targetArchPath.toFile());
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), sourceArchPath.toFile());

        Repository sourceRepo = new RPMMetaRepository(Paths.get(sourceRepositoryPath));
        Repository targetRepo = new RPMMetaRepository(Paths.get(targetRepositoryPath), sourceRepo);

        final String jrrd2TargetPath = targetArchPath.resolve(TestUtils.JRRD2_FILENAME).toString();
        TestUtils.assertFileDoesNotExist(jrrd2TargetPath);
        
        targetRepo.index(m_gpginfo);
        TestUtils.assertFileExists(jrrd2TargetPath);
    }

    @Test
    public void testClone() throws Exception {
        final Path sourceRepositoryPath = Paths.get("target/repositories/RPMMetaRepositoryTest.testClone/source");
        final Path targetRepositoryPath = Paths.get("target/repositories/RPMMetaRepositoryTest.testClone/target");
        final Path sourceArchPath = sourceRepositoryPath.resolve("common").resolve("amd64");
        final Path targetArchPath = targetRepositoryPath.resolve("common").resolve("amd64");

		Files.createDirectories(sourceArchPath);
		Files.createDirectories(targetArchPath);

        FileUtils.copyFileToDirectory(TestUtils.JRRD1_PATH.toFile(), targetArchPath.toFile());
        FileUtils.copyFileToDirectory(TestUtils.JRRD2_PATH.toFile(), sourceArchPath.toFile());
        FileUtils.copyFileToDirectory(TestUtils.JRRD3_PATH.toFile(), sourceArchPath.toFile());

        Repository sourceRepo = new RPMMetaRepository(sourceRepositoryPath);
        Repository targetRepo = new RPMMetaRepository(targetRepositoryPath);
        sourceRepo.index(m_gpginfo);
        targetRepo.index(m_gpginfo);

        final Path jrrd1TargetPath = targetArchPath.resolve(TestUtils.JRRD1_FILENAME);
        final Path jrrd2TargetPath = targetArchPath.resolve(TestUtils.JRRD2_FILENAME);
        final Path jrrd3TargetPath = targetArchPath.resolve(TestUtils.JRRD3_FILENAME);
        TestUtils.assertFileExists(jrrd1TargetPath);
        TestUtils.assertFileDoesNotExist(jrrd2TargetPath);
        TestUtils.assertFileDoesNotExist(jrrd3TargetPath);

        sourceRepo.cloneInto(targetRepositoryPath);
        targetRepo.index(m_gpginfo);

        TestUtils.assertFileDoesNotExist(jrrd1TargetPath);
        TestUtils.assertFileExists(jrrd2TargetPath);
        TestUtils.assertFileExists(jrrd3TargetPath);
    }
}
