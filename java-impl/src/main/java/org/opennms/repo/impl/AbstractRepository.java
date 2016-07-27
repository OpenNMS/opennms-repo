package org.opennms.repo.impl;

import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

import org.apache.commons.io.FileUtils;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.Util;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class AbstractRepository implements Repository {
    private static final Logger LOG = LoggerFactory.getLogger(AbstractRepository.class);

    private final Path m_root;
    private final Repository m_parent;
    private String m_name;

    public AbstractRepository(final Path path) {
        m_root = path.normalize().toAbsolutePath();
        m_parent = null;
        updateMetadata();
    }

    public AbstractRepository(final Path path, final Repository parent) {
        m_root = path.normalize().toAbsolutePath();
        m_parent = parent;
        updateMetadata();
    }

    @Override
    public Path getRoot() {
        return m_root;
    }

    @Override
    public Repository getParent() {
        return m_parent;
    }

    @Override
    public String getName() {
        return m_name;
    }
    
    @Override
    public void setName(final String name) {
        m_name = name;
        updateMetadata();
    }

    @Override
    public Path relativePath(final RepositoryPackage p) {
        return getRoot().relativize(p.getPath());
    }

    @Override
    public void addPackages(final Repository repository) {
        final Collection<RepositoryPackage> fromPackages = repository.getPackages();
        final Map<String,RepositoryPackage> existing = new HashMap<>();
        for (final RepositoryPackage p : getPackages()) {
            final RepositoryPackage existingPackage = existing.get(p.getName());
            if (existingPackage != null) {
                if (existingPackage.isLowerThan(p)) {
                    existing.put(p.getName(), p);
                }
            } else {
                existing.put(p.getName(), p);
            }
        }

        LOG.info("Adding new packages from {} to repository {}", repository, this);
        fromPackages.stream().forEach(pack -> {
            final Path relativePath = repository.relativePath(pack);
            final Path targetPath = getRoot().resolve(relativePath);
            final Path relativeTargetPath = Util.relativize(targetPath);
            try {
                final Path parent = targetPath.getParent();
                final RepositoryPackage existingPackage = existing.get(pack.getName());
                if (existingPackage.isLowerThan(pack)) {
                    LOG.debug("Copying {} to {}", pack, relativeTargetPath);
                    if (!parent.toFile().exists()) {
                        Files.createDirectories(parent);
                    }
                    FileUtils.copyFile(pack.getFile(), targetPath.toFile());
                } else {
                    LOG.debug("NOT copying {} to {} ({} is newer)", pack, relativeTargetPath, existingPackage);
                }
            } catch (final IOException e) {
                throw new RepositoryException("Failed to copy " + pack + " to " + relativeTargetPath, e);
            }
        });
    }

    @Override
    public void index() throws RepositoryIndexException {
        index(null);
    }

    @Override
    public int compareTo(final Repository o) {
        int ret = m_root.compareTo(o.getRoot());
        if (ret == 0) {
            ret = m_parent.compareTo(o.getParent());
        }
        return ret;
    }

    @Override
    public abstract String toString();
    
    protected void updateMetadata() {
        LOG.info("Updating metadata in repository {}", this);
        if (m_name == null) {
            m_name = getRoot().getFileName().toString();
        }
        final Properties props = new Properties();
        props.put("name", getName());
        final Repository parent = getParent();
        if (parent != null) {
            props.put("parent", getRoot().relativize(parent.getRoot().normalize().toAbsolutePath()).toString());
        }

        LOG.debug("Repository metadata: {}", props);
        if (!getRoot().toFile().exists()) {
            try {
                Files.createDirectories(getRoot());
            } catch (final IOException e) {
                throw new RepositoryException(e.getMessage(), e);
            }
        }
        try (final FileWriter fw = new FileWriter(getRoot().resolve(REPO_METADATA_FILENAME).toFile())) {
            props.store(fw, "RPMRepository Metadata");
        } catch (final IOException e) {
            throw new RepositoryException(e.getMessage(), e);
        }
    }
}
