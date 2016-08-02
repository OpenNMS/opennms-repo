package org.opennms.repo.api;

import java.io.IOException;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.nio.file.Path;
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

	public RepositoryMetadata(final Path root, final Class<? extends Repository> type) {
		m_root = root.normalize().toAbsolutePath();
		m_type = type;
		m_name = m_root.getFileName().toString();
		m_parent = initializeParent(m_root);
	}

	public RepositoryMetadata(final Path root, final Class<? extends Repository> type, final Path parentRoot, final Class<? extends Repository> parentType) {
		m_root = root.normalize().toAbsolutePath();
		m_type = type;
		m_parent = new RepositoryMetadata(parentRoot.normalize().toAbsolutePath(), parentType);
	}

	private RepositoryMetadata initializeParent(final Path root) {
		Path parent = null;
		String parentType = null;
		try {
			final Map<String,String> metadata = Util.readMetadata(root);
			if (metadata.containsKey(METADATA_KEY_PARENT) && metadata.containsKey(METADATA_KEY_PARENT_TYPE)) {
				final String parentString = metadata.get(METADATA_KEY_PARENT);
				parent = root.resolve(parentString).normalize().toAbsolutePath();
				parentType = metadata.get(METADATA_KEY_PARENT_TYPE);
				LOG.debug("initializeParent: root={}, parent={}, parentType={}", root, parent, parentType);
				final Class<? extends Repository> type = Class.forName(parentType).asSubclass(Repository.class);
				return new RepositoryMetadata(parent, type);
			}
		} catch (final IOException e) {
			LOG.warn("Failed to read repository metadata from {}", root);
			throw new RepositoryException(e);
		} catch (final ClassNotFoundException e) {
			LOG.warn("Failed to instantiate parent repository class {} in path {}", parentType, parent);
			throw new RepositoryException(e);
		}
		return null;
	}

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
		m_lastIndexed  = System.currentTimeMillis();
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

    		self.put(METADATA_KEY_LAST_INDEXED, String.valueOf(m_lastIndexed));

    		// update parent info
    		if (m_parent != null) {
                self.put(METADATA_KEY_PARENT, m_root.relativize(m_parent.getRoot().normalize().toAbsolutePath()).toString());
                self.put(METADATA_KEY_PARENT_TYPE, m_parent.getType().getName());
    		}

            boolean dirty = false;

            for (final String key : self.keySet()) {
            	if (!Objects.equals(self.get(key), onDisk.get(key))) {
            		dirty = true;
            		break;
            	}
            }
            
            if (dirty) {
            	LOG.debug("Metadata has changed. Updating {}", this);
            	Util.writeMetadata(self, m_root);
            } else {
            	LOG.debug("Metadata is unchanged. Leaving {}", this);
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
		//return "RepositoryMetadata[name=" + getName() + ",type=" + getType().getSimpleName() + ",parent=" + hasParent() + "]:" + Util.relativize(getRoot());
		return "RepositoryMetadata[name=" + getName() + ",type=" + getType().getSimpleName() + ",parent=" + hasParent() + "]";
	}

    @Override
    public int hashCode() {
        return Objects.hash(m_root, m_type, m_name, m_parent);
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
                Objects.equals(m_name, other.m_name) &&
                Objects.equals(m_parent, other.m_parent);
    }

    public static RepositoryMetadata getInstance(final Path path) {
		String type = null;
		try {
			final Map<String,String> metadata = Util.readMetadata(path);
			LOG.debug("got metadata {} from path {}", metadata, path);
			if (metadata.containsKey(METADATA_KEY_TYPE)) {
				type = metadata.get(METADATA_KEY_TYPE);
				final Class<? extends Repository> c = Class.forName(type).asSubclass(Repository.class);
				return new RepositoryMetadata(path, c);
			}
		} catch (final IOException e) {
			LOG.warn("Failed to get instance of metadata for repository at {}", path);
			throw new RepositoryException(e);
		} catch (final ClassNotFoundException e) {
			LOG.warn("Repository at {} is of unknown type ({})", path, type);
			throw new RepositoryException(e);
		}
		throw new IllegalArgumentException("Path " + path + " is not a repository!");
	}
}
