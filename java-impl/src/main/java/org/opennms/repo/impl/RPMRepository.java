package org.opennms.repo.impl;

import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import org.bouncycastle.util.io.pem.PemObject;
import org.bouncycastle.util.io.pem.PemWriter;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMRepository implements Repository {
    private static final Logger LOG = LoggerFactory.getLogger(RPMRepository.class);

    private final Path m_root;

    public RPMRepository(final String path) {
        m_root = Paths.get(path).toAbsolutePath();
    }

    public RPMRepository(final Path path) {
        m_root = path.toAbsolutePath();
    }

    @Override
    public Path getRoot() {
        return m_root;
    }

    @Override
    public boolean exists() {
        return m_root.toFile().exists();
    }

    @Override
    public void index(final GPGInfo gpginfo) throws RepositoryIndexException {
        LOG.debug("indexing {}", m_root);
        try {
            if (!m_root.toFile().exists()) {
                Files.createDirectories(m_root);
            }
            final CreaterepoCommand command = new CreaterepoCommand(m_root);
            command.run();

            if (gpginfo == null) {
                LOG.warn("Skipping repomd.xml signing!");
            } else {
                final Path repomdfile = m_root.resolve("repodata/repomd.xml");

                final Path signfile = Paths.get(repomdfile.toString() + ".asc");
                GPGUtils.detach_sign(repomdfile, signfile, gpginfo, false);

                final Path keyfile = Paths.get(repomdfile.toString() + ".key");
                try(final FileWriter fw = new FileWriter(keyfile.toFile()); final PemWriter writer = new PemWriter(fw);) {
                    writer.writeObject(new PemObject("PGP PUBLIC KEY BLOCK", gpginfo.getPublicKey().getEncoded()));
                }
            }
        } catch (final RepositoryException | IOException | InterruptedException e) {
            throw new RepositoryIndexException("Failed to run `createrepo`!", e);
        }
    }

}
