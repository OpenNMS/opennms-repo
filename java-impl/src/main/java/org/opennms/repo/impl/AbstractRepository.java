package org.opennms.repo.impl;

import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.lang.reflect.Constructor;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.FileTime;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Properties;
import java.util.concurrent.ConcurrentHashMap;

import org.apache.commons.io.FileUtils;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.Util;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class AbstractRepository implements Repository {
    private static final RepositoryPackage[] EMPTY_REPOSITORY_PACKAGE_ARRAY = new RepositoryPackage[0];

    private static final Logger LOG = LoggerFactory.getLogger(AbstractRepository.class);

    private final Path m_root;
    private final Repository m_parent;
    private String m_name;
    private long m_lastIndexed = -1;
    private Map<String,String> m_metadata = new ConcurrentHashMap<>();
    private Map<String,RepositoryPackage> m_packageCache = new HashMap<>();

    public AbstractRepository(final Path path) {
        m_root = path.normalize().toAbsolutePath();
        m_parent = initializeParent();
        updateMetadata();
    }

    public AbstractRepository(final Path path, final Repository parent) {
        m_root = path.normalize().toAbsolutePath();
        m_parent = parent;
        updateMetadata();
    }

    @Override
    public int hashCode() {
        return Objects.hash(m_name, m_root, m_parent);
    }

    @Override
    public boolean equals(final Object obj) {
        if (this == obj) {
            return true;
        }
        if (obj == null) {
            return false;
        }
        if (getClass() != obj.getClass()) {
            return false;
        }
        AbstractRepository other = (AbstractRepository) obj;
        return Objects.equals(m_name, other.m_name) &&
                Objects.equals(m_root, other.m_root) &&
                Objects.equals(m_parent, other.m_parent);
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
    public boolean hasParent() {
    	return m_parent != null;
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

    public Map<String,String> getMetadata() {
    	return m_metadata;
    }
    
    public void setMetadata(final Map<String,String> metadata) {
    	m_metadata = metadata;
    }

    @Override
    public Path relativePath(final RepositoryPackage p) {
        return getRoot().relativize(p.getPath());
    }

    protected RepositoryPackage getPackage(final String packageName) {
        return m_packageCache.get(packageName);
    }

    @Override
    public<T extends Repository> void addPackages(final T repository) {
    	LOG.debug("addPackages({})", repository);
    	repository.refresh();
        final Collection<RepositoryPackage> fromPackages = repository.getPackages();

        LOG.info("Adding new packages from {} to repository {}", repository, this);
        addPackages(fromPackages.toArray(EMPTY_REPOSITORY_PACKAGE_ARRAY));
    }

    @Override
    public void addPackages(final RepositoryPackage... packages) {
    	LOG.debug("addPackages: {}", Arrays.asList(packages));
    	refresh();
        for (final RepositoryPackage pack : packages) {
            try {
                Path targetDirectory = this.getRoot();
                if (pack.getArchitecture() != null) {
                    targetDirectory = this.getRoot().resolve(pack.getArchitecture().toString().toLowerCase());
                }
                final Path targetPath = targetDirectory.resolve(pack.getFile().getName());
                final Path relativeTargetPath = Util.relativize(targetPath);
                final RepositoryPackage existingPackage = getPackage(pack.getName());
                if (existingPackage == null || existingPackage.isLowerThan(pack)) {
                    LOG.debug("Copying {} to {}", pack, relativeTargetPath);
                    final Path parent = targetPath.getParent();
                    if (!parent.toFile().exists()) {
                        Files.createDirectories(parent);
                    }
                    FileUtils.copyFile(pack.getFile(), targetPath.toFile());
                    FileUtils.touch(targetPath.toFile());
                    updatePackage(pack);
                    m_lastIndexed = -1;
                } else {
                    LOG.debug("NOT copying {} to {} ({} is newer)", pack, relativeTargetPath, existingPackage);
                }
            } catch (final IOException e) {
                throw new RepositoryException(e);
            }
        }
    }

    protected void updatePackage(final RepositoryPackage pack) {
    	m_packageCache.put(pack.getName(), pack);
    }

    protected Optional<FileTime> getLatestFileTime() {
        final Path root = getRoot();
        try {
            return Files.walk(root).filter(path -> {
            	return path.toFile().isFile() && !RepoUtils.isMetadata(path);
            }).map(path -> {
                try {
                    final Path filePath = path;
					return Util.getFileTime(filePath);
                } catch (final Exception e) {
                    return null;
                }
            }).max((a, b) -> {
                return a.compareTo(b);
            });
        } catch (final Exception e) {
            LOG.warn("Failed while checking for a dirty repository: {}", this, e);
            return Optional.empty();
        }
    }

    @Override
    public void refresh() {
    	LOG.info("Refreshing repository {}", this);
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
        LOG.debug("Repository {} packages: {}", this, existing);
        m_packageCache = existing;
        updateMetadata();
    }

    @Override
    public void index() throws RepositoryIndexException {
        index(null);
    }

    protected long getLastIndexed() {
    	return m_lastIndexed;
    }

    protected void updateLastIndexed() {
    	m_lastIndexed = System.currentTimeMillis();
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
    public String toString() {
        return getClass().getSimpleName() + "@" + System.identityHashCode(this) + ":" + getName() + "(parent=" + hasParent() + "):" + Util.relativize(getRoot());
    }
    
    public void updateMetadata() {
    	try {
    		final Map<String,String> onDisk = readMetadata();
    		final Map<String,String> current = getMetadata();

    		// update name
        	if (m_name == null) {
                m_name = getRoot().getFileName().toString();
            }
    		current.put("name", getName());
    		current.put("type", getClass().getName());

    		current.put("lastIndexed", String.valueOf(m_lastIndexed));

    		// update parent info
            final Repository parent = getParent();
            if (parent != null) {
                current.put("parent", getRoot().relativize(parent.getRoot().normalize().toAbsolutePath()).toString());
                current.put("parentType", parent.getClass().getName());
            }

            boolean dirty = false;

            for (final String key : current.keySet()) {
            	if (!Objects.equals(current.get(key), onDisk.get(key))) {
            		dirty = true;
            		break;
            	}
            }
            
            if (dirty) {
            	LOG.debug("Metadata has changed. Updating {}", this);
            	setMetadata(current);
            	writeMetadata(current);
            } else {
            	LOG.debug("Metadata is unchanged. Leaving {}", this);
            }
    	} catch (final IOException e) {
    		throw new RepositoryException(e);
    	}
    }

    protected Map<String,String> readMetadata() throws IOException {
    	final Map<String,String> metadata = new ConcurrentHashMap<>();
    	final File metadataFile = getRoot().resolve(REPO_METADATA_FILENAME).toFile();
    	if (metadataFile.exists()) {
        	try (final FileReader fr = new FileReader(metadataFile)) {
            	final Properties props = new Properties();
            	props.load(fr);
            	for (final Map.Entry<Object,Object> entry : props.entrySet()) {
            		final Object value = entry.getValue();
					metadata.put(entry.getKey().toString(), value == null? null : value.toString());
            	}
			}
    	}
    	return metadata;
    }

    protected void writeMetadata(final Map<String,String> metadata) throws IOException {
    	final Properties props = new Properties();
    	for (final Map.Entry<String,String> entry : metadata.entrySet()) {
    		props.put(entry.getKey(), entry.getValue());
    	}
    	if (!getRoot().toFile().exists()) {
    		Files.createDirectories(getRoot());
    	}
    	try (final FileWriter fw = new FileWriter(getRoot().resolve(REPO_METADATA_FILENAME).toFile())) {
        	props.store(fw, "Repository Metadata");
    	}
    }

    @Override
    public<T extends Repository> T as(final Class<T> repository) {
        return repository.cast(this);
    }

    protected Repository initializeParent() {
        final Map<String,String> metadata = getMetadata();
        if (metadata.containsKey("parent") && metadata.containsKey("parentType")) {
        	final String parentType = metadata.get("parentType");
        	final String parentPath = metadata.get("parent");
        	LOG.debug("Initializing parent {}={}", parentPath, parentType);
        	try {
				final Class<? extends Repository> clazz = Class.forName(parentType).asSubclass(Repository.class);
				final Constructor<? extends Repository> constructor = clazz.getConstructor(Path.class);
				final Repository instance = constructor.newInstance(Paths.get(parentPath));
				LOG.debug("Got parent: {}", instance);
				return instance;
			} catch (final Exception e) {
				throw new RepositoryException("Failed to create parent of type " + parentType, e);
			}
        } else {
        	LOG.debug("No parent found for {}", this);
        }
        return null;
    }
}
