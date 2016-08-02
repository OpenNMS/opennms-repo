package org.opennms.repo.impl.rpm;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Collection;
import java.util.Collections;
import java.util.Optional;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.AbstractRepository;
import org.opennms.repo.impl.GPGUtils;
import org.opennms.repo.impl.RepoUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMRepository extends AbstractRepository {
    private static final Logger LOG = LoggerFactory.getLogger(RPMRepository.class);

    public RPMRepository(final Path path) {
        super(path);
    }

    public RPMRepository(final Path path, final Repository parent) {
        super(path, parent);
    }

    @Override
    public Collection<RepositoryPackage> getPackages() {
        final Path root = getRoot();
        if (!root.toFile().exists() || !root.toFile().isDirectory()) {
        	return Collections.emptyList();
        }

        try {
            return Files.walk(root).filter(path -> {
                return path.toString().endsWith(".rpm") && path.toFile().isFile();
            }).map(path -> {
                try {
                    return RPMUtils.getPackage(path.toFile());
                } catch (final Exception e) {
                    return null;
                }
            }).sorted().collect(Collectors.toList());
        } catch (final IOException e) {
            throw new RepositoryException("Unable to walk " + root + " directory for RPMs", e);
        }
    }

    @Override
    public boolean isValid() {
        if (!getRoot().toFile().exists()) {
            return false;
        }
        return getRoot().resolve("repodata").resolve("repomd.xml").toFile().exists() &&
                getRoot().resolve(REPO_METADATA_FILENAME).toFile().exists();
    }

    private void ensureRootExists() {
        final Path root = getRoot();
        try {
            if (!root.toFile().exists()) {
                Files.createDirectories(root);
            }
        } catch (final Exception e) {
            throw new RepositoryIndexException("Unable to create repository root '" + root + "'!", e);
        }
        updateMetadata();
    }

    @Override
    public void index(final GPGInfo gpginfo) throws RepositoryIndexException {
        LOG.info("index(): {}", this);
        final Path root = getRoot();
        ensureRootExists();

        final Repository parentRepository = getParent();
        if (parentRepository != null) {
            addPackages(parentRepository);
        } else {
            LOG.debug("No parent {}", this);
        }

        refresh();

        if (!isDirty()) {
            LOG.info("RPM repository not changed: {}", this);
            return;
        }

        ensureRootExists();
        generateDeltas();

        LOG.info("Indexing RPM repository: {}", this);
        final CreaterepoCommand command = new CreaterepoCommand(root);
        command.run();
        final Path repomdfile = root.resolve("repodata").resolve("repomd.xml");

        if (gpginfo == null) {
            LOG.warn("Skipping repomd.xml signing!");
        } else {
            final String ascPath = repomdfile.toString() + ".asc";
            final String keyPath = repomdfile.toString() + ".key";

            try {
                final Path signfile = Paths.get(ascPath);
                GPGUtils.detach_sign(repomdfile, signfile, gpginfo, false);
            } catch (final InterruptedException | IOException e) {
                LOG.debug("Failed to detach-sign {}", repomdfile, e);
                throw new RepositoryException(e);
            }

            final Path keyfile = Paths.get(keyPath);
            try {
                GPGUtils.exportKeyRing(keyfile, gpginfo.getPublicKeyRing());
            } catch (final IOException e) {
                LOG.debug("Failed to export keyring to {}", keyfile, e);
                throw new RepositoryException(e);
            }

            try {
                FileUtils.touch(new File(ascPath));
                FileUtils.touch(new File(keyPath));
            } catch (final IOException e) {
                LOG.debug("Failed to touch {} and {}", ascPath, keyPath, e);
                throw new RepositoryException(e);
            }
        }

        try {
            FileUtils.touch(repomdfile.toFile());
        } catch (final IOException e) {
            LOG.debug("Failed to touch {}", repomdfile, e);
            throw new RepositoryException(e);
        }
        updateLastIndexed();
    }

    public void generateDeltas() throws RepositoryException {
        final Path root = getRoot();
        LOG.info("Generating deltas for RPM repository: {}", this);
        RPMUtils.generateDeltas(root.toFile());
        LOG.info("Finished generating deltas for RPM repository: {}", this);
    }

    protected boolean isDirty() {
        final Path root = getRoot();
        try {
            final long lastIndexed = getLastIndexed();
            final Optional<Long> res = Files.walk(root).filter(path -> {
                return !path.startsWith(root.resolve("repodata")) && !RepoUtils.isMetadata(path);
            }).map(path -> {
                try {
                    final Path filePath = path;
                    return Util.getFileTime(filePath).toMillis();
                } catch (final Exception e) {
                    return null;
                }
            }).max((a, b) -> {
                return a.compareTo(b);
            });

            LOG.debug("newest repodata edit: {} {}", lastIndexed, this);
            if (res.isPresent()) {
                final long reduced = res.get();
                LOG.debug("newest other file: {} {}", reduced, this);
                return reduced > lastIndexed;
            } else {
                LOG.warn("No file times found in repository {}!", this);
                return false;
            }
        } catch (final Exception e) {
            LOG.warn("Failed while checking for a dirty repository: {}", this, e);
            return true;
        }
    }

    @Override
    public Repository cloneInto(final Path to) {
        RepoUtils.cloneDirectory(getRoot(), to);
        return new RPMRepository(to, this);
    }
}