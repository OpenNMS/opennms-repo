package org.opennms.repo.api;

import java.io.IOException;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RepositoryMetadata {
	public static final String METADATA_KEY_NAME = "name";
	public static final String METADATA_KEY_TYPE = "type";
	public static final String METADATA_KEY_PARENT = "parent";
	public static final String METADATA_KEY_PARENT_TYPE = "parentType";
	public static final String METADATA_KEY_LAST_INDEXED = "lastIndexed";

	private static final Logger LOG = LoggerFactory.getLogger(RepositoryMetadata.class);

	private final Path m_root;
	private final Class<? extends Repository> m_type;
	private final RepositoryMetadata m_parent;
	private String m_name;
	private long m_lastIndexed = -1;

	protected RepositoryMetadata(final Path root, final Class<? extends Repository> type, final Path parentRoot, final Class<? extends Repository> parentType, final String name, final Long lastIndexed) {
		m_root = root.normalize().toAbsolutePath();
		m_type = type;
		if (parentRoot != null && parentType != null) {
			m_parent = RepositoryMetadata.getInstance(parentRoot, parentType);
		} else {
			m_parent = null;
		}
		m_name = name;
		m_lastIndexed = lastIndexed == null? -1 : lastIndexed;
	}

	/*
	private RepositoryMetadata initializeParent(final Path root) {
		Path parentPath = null;
		String parentType = null;
		try {
			final Map<String,String> metadata = Util.readMetadata(root);
			if (metadata.containsKey(METADATA_KEY_PARENT) && metadata.containsKey(METADATA_KEY_PARENT_TYPE)) {
				final String parentString = metadata.get(METADATA_KEY_PARENT);
				parentPath = root.resolve(parentString).normalize().toAbsolutePath();
				parentType = metadata.get(METADATA_KEY_PARENT_TYPE);
				LOG.debug("initializeParent: root={}, parent={}, parentType={}", root, parentPath, parentType);
				final Class<? extends Repository> type = Class.forName(parentType).asSubclass(Repository.class);
				return RepositoryMetadata.getInstance(parentPath, type);
			}
		} catch (final IOException e) {
			LOG.warn("Failed to read repository metadata from {}", root);
			throw new RepositoryException(e);
		} catch (final ClassNotFoundException e) {
			LOG.warn("Failed to instantiate parent repository class {} in path {}", parentType, parentPath);
			throw new RepositoryException(e);
		}
		return null;
	}
	*/

	public Path getRoot() {
		return m_root;
	}

	public String getName() {
		return m_name;
	}

	public void setName(final String name) {
		m_name = name;
	}

	public Class<? extends Repository> getType() {
		return m_type;
	}

	public long getLastIndexed() {
		return m_lastIndexed;
	}

	public void resetLastIndexed() {
		m_lastIndexed = -1;
	}

	public void touchLastIndexed() {
		m_lastIndexed = System.currentTimeMillis();
	}

	public boolean hasParent() {
		return m_parent != null;
	}

	public void store() {
    	try {
    		final Map<String,String> onDisk = Util.readMetadata(m_root);
    		final Map<String,String> self = new LinkedHashMap<>();

    		// update name
        	if (m_name == null) {
                m_name = m_root.getFileName().toString();
            }
    		self.put(METADATA_KEY_NAME, getName());
    		self.put(METADATA_KEY_TYPE, getType().getName());

    		self.put(METADATA_KEY_LAST_INDEXED, Long.valueOf(getLastIndexed()).toString());

    		// update parent info
    		if (m_parent != null) {
                self.put(METADATA_KEY_PARENT, m_root.relativize(m_parent.getRoot().normalize().toAbsolutePath()).toString());
                self.put(METADATA_KEY_PARENT_TYPE, m_parent.getType().getName());
    		}

            boolean dirty = false;

            for (final String key : self.keySet()) {
            	final String myValue = self.get(key);
				final String otherValue = onDisk.get(key);
				if (!Objects.equals(myValue, otherValue)) {
            		dirty = true;
            		break;
            	}
            }
            
            if (dirty) {
            	LOG.debug("Metadata has changed. Updating {}", this);
            	Util.writeMetadata(self, m_root);
            } else {
            	LOG.trace("Metadata is unchanged. Leaving {} alone", this);
            }
    	} catch (final IOException e) {
    		throw new RepositoryException(e);
    	}
	}

	public RepositoryMetadata getParentMetadata() {
		return m_parent;
	}

	public Repository getRepositoryInstance() throws RepositoryException {
		try {
			if (hasParent()) {
				LOG.debug("has parent {}", this);
				final Constructor<? extends Repository> constructor = m_type.getConstructor(Path.class, Repository.class);
				return constructor.newInstance(getRoot(), m_parent.getRepositoryInstance());
			} else {
				LOG.debug("no parent {}", this);
				final Constructor<? extends Repository> constructor = m_type.getConstructor(Path.class);
				return constructor.newInstance(getRoot());
			}
		} catch (final NoSuchMethodException | SecurityException | InstantiationException | IllegalAccessException | IllegalArgumentException | InvocationTargetException e) {
			throw new RepositoryException(e);
		}
	}

	@Override
	public String toString() {
		return "RepositoryMetadata[name=" + getName() + ",type=" + getType().getSimpleName() + ",lastIndexed=" + m_lastIndexed + ",parent=" + hasParent() + "]";
	}

    @Override
    public int hashCode() {
        return Objects.hash(m_root, m_type /*, m_name */, m_parent);
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
        RepositoryMetadata other = (RepositoryMetadata) obj;
        return Objects.equals(m_root, other.m_root) &&
                Objects.equals(m_type, other.m_type) &&
                //Objects.equals(m_name, other.m_name) &&
                Objects.equals(m_parent, other.m_parent);
    }

    public static RepositoryMetadata getInstance(final Path path, final Class<? extends Repository> type) {
    	return RepositoryMetadata.getInstance(path, type, null, null);
    }

    public static RepositoryMetadata getInstance(final Path path, final Class<? extends Repository> type, final Path parentPath, final Class<? extends Repository> parentType) {
    	Class<? extends Repository> repoType = type;

    	Path detectedParentPath = parentPath;
    	Class<? extends Repository> parentRepoType = parentType;
		try {
			final Map<String,String> metadata = Util.readMetadata(path);
			LOG.trace("got metadata {} from path {}", metadata, path);

			// use the type from the .metadata file, if found
			try {
				if (metadata.containsKey(METADATA_KEY_TYPE)) {
					final String typeValue = metadata.get(METADATA_KEY_TYPE);
					repoType = Class.forName(typeValue).asSubclass(Repository.class);
				}
			} catch (final ClassNotFoundException e) {
				LOG.warn("Repository metadata for {} does not have an existing type, and no type was passed for initialization.", path);
				throw new RepositoryException(e);
			}

			// use the parent path from the .metadata file, if not passed
			if (detectedParentPath == null && metadata.containsKey(METADATA_KEY_PARENT)) {
				detectedParentPath = path.resolve(Paths.get(metadata.get(METADATA_KEY_PARENT)));
			}
			if (detectedParentPath != null) {
				detectedParentPath = detectedParentPath.normalize().toAbsolutePath();
			}

			// use the parent type from the .metadata file, if found
			try {
				if (parentRepoType == null && metadata.containsKey(METADATA_KEY_PARENT_TYPE)) {
					final String typeValue = metadata.get(METADATA_KEY_PARENT_TYPE);
					parentRepoType = Class.forName(typeValue).asSubclass(Repository.class);
				}
			} catch (final ClassNotFoundException e) {
				LOG.warn("Repository metadata for {} does not have an existing parent type, and no parent type was passed for initialization.", path);
				throw new RepositoryException(e);
			}

			if (repoType != null) {
				Long lastIndexed = null;
				if (metadata.containsKey(METADATA_KEY_LAST_INDEXED)) {
					lastIndexed = Long.valueOf(metadata.get(METADATA_KEY_LAST_INDEXED));
				}
				String name = metadata.get(METADATA_KEY_NAME);
				if (name == null) {
					name = path.getFileName().toString();
				}
				return new RepositoryMetadata(path.normalize().toAbsolutePath(), repoType, detectedParentPath, parentRepoType, name, lastIndexed);
			}
		} catch (final IOException e) {
			LOG.warn("Failed to get instance of metadata for repository at {}", path);
			throw new RepositoryException(e);
		}
		throw new IllegalArgumentException("Path " + path + " is not a repository!");
	}
}
