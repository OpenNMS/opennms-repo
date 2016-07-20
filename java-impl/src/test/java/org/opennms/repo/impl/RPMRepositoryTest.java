package org.opennms.repo.impl;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import org.bouncycastle.openpgp.PGPSecretKey;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Repository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMRepositoryTest {
    private static final Logger LOG = LoggerFactory.getLogger(RPMRepositoryTest.class);

    @Before
    @After
    public void cleanUp() throws IOException {
        recursiveDelete(Paths.get("target/repositories"));
    }

    @Test
    public void testCreateRepository() throws Exception {
        Repository repo = new RPMRepository("target/repositories/testCreateRepository");
        assertFalse(repo.exists());

        final String keyId = "foo@bar.com";
        final String passphrase = "12345";
        final PGPSecretKey key = GPGUtils.generateKey(keyId, passphrase);
        final GPGInfo gpginfo = new GPGInfo(keyId, passphrase, key);
        repo.index(gpginfo);
        assertFileExists("target/repositories/testCreateRepository/repodata");
        assertFileExists("target/repositories/testCreateRepository/repodata/repomd.xml");
        assertFileExists("target/repositories/testCreateRepository/repodata/repomd.xml.asc");
        assertFileExists("target/repositories/testCreateRepository/repodata/repomd.xml.key");
    }

    private void assertFileExists(final String path) {
        final Path p = Paths.get(path);
        assertTrue("File/directory '" + path + "' must exist.", p.toFile().exists());
        assertTrue("File/directory '" + path + "' must not be empty.", p.toFile().length() > 0);
    }

    private void recursiveDelete(final Path path) throws IOException {
        if (path.toFile().exists()) {
            //LOG.debug("path={}", path);
            for (final File file : path.toFile().listFiles()) {
                if (file.isDirectory()) {
                    recursiveDelete(file.toPath());
                } else {
                    LOG.debug("  delete: {}", file);
                    file.delete();
                }
            }
            //LOG.debug("delete: {}", path);
            Files.delete(path);
        }
    }
}
