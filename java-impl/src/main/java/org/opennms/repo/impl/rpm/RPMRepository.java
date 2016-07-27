package org.opennms.repo.impl.rpm;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.FileTime;
import java.time.Instant;
import java.util.Collection;
import java.util.Optional;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.PackageUtils;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.AbstractRepository;
import org.opennms.repo.impl.GPGUtils;
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
        final Path repomdfile = getRoot().resolve("repodata/repomd.xml");
        return repomdfile.toFile().exists();
    }

    @Override
    public void index(final GPGInfo gpginfo) throws RepositoryIndexException {
        final Path root = getRoot();
        try {
            if (!root.toFile().exists()) {
                Files.createDirectories(root);
            }
        } catch (final Exception e) {
            throw new RepositoryIndexException("Unable to create repository root '" + root + "'!", e);
        }

        final Repository parentRepository = getParent();
        if (parentRepository != null) {
            addPackages(parentRepository);
        }

        if (!isDirty()) {
            LOG.info("RPM repository not changed: {}", this);
            return;
        }

        generateDeltas();

        LOG.info("Indexing RPM repository: {}", this);
        try {
            final CreaterepoCommand command = new CreaterepoCommand(root);
            command.run();

            if (gpginfo == null) {
                LOG.warn("Skipping repomd.xml signing!");
            } else {
                final Path repomdfile = root.resolve("repodata/repomd.xml");

                final Path signfile = Paths.get(repomdfile.toString() + ".asc");
                GPGUtils.detach_sign(repomdfile, signfile, gpginfo, false);

                final Path keyfile = Paths.get(repomdfile.toString() + ".key");
                GPGUtils.exportKeyRing(keyfile, gpginfo.getPublicKeyRing());
            }
        } catch (final RepositoryException | IOException | InterruptedException e) {
            throw new RepositoryIndexException("Failed to run `createrepo`!", e);
        }
    }

    public void generateDeltas() throws RepositoryException {
        final Path root = getRoot();
        LOG.info("Generating deltas for RPM repository: {}", this);
        RPMUtils.generateDeltas(root.toFile());
    }

    private boolean isDirty() {
        final Path root = getRoot();
        try {
            final FileTime newestRepodata = getNewestRepodataEdit();
            final Optional<FileTime> res = Files.walk(root).filter(path -> {
                return !path.startsWith(root.resolve("repodata"));
            }).map(path -> {
                try {
                    return PackageUtils.getFileTime(path);
                } catch (final Exception e) {
                    return null;
                }
            }).max((a, b) -> {
                return a.compareTo(b);
            });
            
            if (res.isPresent()) {
                final FileTime reduced = res.get();
                if (reduced.compareTo(newestRepodata) == 1) {
                    return true;
                } else {
                    return false;
                }
            } else {
                return false;
            }
        } catch (final Exception e) {
            LOG.warn("Failed while checking for a dirty repository: {}", this, e);
            return true;
        }
    }

    private FileTime getNewestRepodataEdit() throws IOException {
        FileTime epoch = FileTime.from(Instant.EPOCH);
        final Path repodata = getRoot().resolve("repodata");
        if (!repodata.toFile().exists()) {
            return epoch;
        }
        final Optional<FileTime> res = Files.walk(repodata).map(path -> {
            try {
                return PackageUtils.getFileTime(path);
            } catch (final Exception e) {
                return null;
            }
        }).max((a, b) -> {
            return a.compareTo(b);
        });
        if (res.isPresent()) {
            final FileTime reduced = res.get();
            if (reduced.compareTo(epoch) == 1) {
                return reduced;
            }
        }
        return epoch;
    }

    @Override
    public String toString() {
        return "RPMRepository:" + Util.relativize(getRoot());
    }

    @Override
    public Repository cloneInto(final Path to) {
        final Path path = to.normalize().toAbsolutePath();
        LOG.info("Cloning repository {} into {}", this, path);
        //LOG.debug("clone: {}", path);
        try {
            FileUtils.cleanDirectory(path.toFile());
            Files.walk(getRoot()).forEach(p -> {
                try {
                    final Path relativePath = getRoot().relativize(p);
                    if (relativePath.getFileName().toString().equals(REPO_METADATA_FILENAME)) {
                        return;
                    }
                    final Path targetPath = path.resolve(relativePath).normalize();
                    if (p.toFile().isDirectory()) {
                        LOG.debug("clone: creating directory {}", Util.relativize(targetPath));
                        Files.createDirectories(targetPath);
                    } else {
                        LOG.debug("clone: Copying {} to {}", Util.relativize(p), Util.relativize(targetPath));
                        Files.createLink(targetPath, p);
                    }
                } catch (final IOException e) {
                    throw new RepositoryException(e);
                }
            });
        } catch (final IOException e) {
            throw new RepositoryException(e);
        }
        return new RPMRepository(to, this);
    }
}
