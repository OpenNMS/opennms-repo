package org.opennms.repo.api;

import java.io.File;
import java.io.IOException;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.SortedSet;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RepositoryMetadata implements Comparable<RepositoryMetadata> {
	public static final String METADATA_KEY_NAME = "name";
	public static final String METADATA_KEY_TYPE = "type";
	public static final String METADATA_KEY_PARENTS = "parents";
	public static final String METADATA_KEY_LAST_INDEXED = "lastIndexed";

	private static final Logger LOG = LoggerFactory.getLogger(RepositoryMetadata.class);

	private final Path m_root;
	private final Class<? extends Repository> m_type;
	private Set<RepositoryMetadata> m_parents = new LinkedHashSet<>();
	private String m_name;
	private long m_lastIndexed = -1;

	protected RepositoryMetadata(final Path root, final Class<? extends Repository> type, final String name, final Long lastIndexed, final Set<RepositoryMetadata> parents) {
		m_root = root.normalize().toAbsolutePath();
		m_type = type;
		m_name = name;
		m_lastIndexed = lastIndexed == null ? -1 : lastIndexed;
		if (parents == null) {
			m_parents.clear();
		} else {
			m_parents = parents;
		}
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
		m_lastIndexed = System.currentTimeMillis();
	}

	public boolean hasParent() {
		return m_parents.size() > 0;
	}

	public void store() {
		try {
			final Map<String, String> onDisk = Util.readMetadata(m_root);
			final Map<String, String> self = new LinkedHashMap<>();

			// update name
			if (m_name == null) {
				m_name = m_root.getFileName().toString();
			}
			self.put(METADATA_KEY_NAME, getName());
			self.put(METADATA_KEY_TYPE, getType().getName());

			self.put(METADATA_KEY_LAST_INDEXED, Long.valueOf(getLastIndexed()).toString());

			// update parent info
			if (m_parents.size() > 0) {
				self.put(METADATA_KEY_PARENTS, String.join(",", Util.getStream(m_parents).map(parent -> {
					return parent.getRoot().normalize().toAbsolutePath().toString();
				}).collect(Collectors.toList())));
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

	public Set<RepositoryMetadata> getParentMetadata() {
		return m_parents;
	}

	public Repository getRepositoryInstance() throws RepositoryException {
		try {
			if (hasParent()) {
				LOG.debug("has parent {}", this);
				final Constructor<? extends Repository> constructor = m_type.getConstructor(Path.class, SortedSet.class);
				return constructor.newInstance(getRoot(), Util.newSortedSet(Util.getStream(m_parents).map(repoMetadata -> {
					return repoMetadata.getRepositoryInstance();
				}).collect(Collectors.toList())));
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
		return Objects.hash(m_root, m_type /* , m_name */, m_parents);
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
		return Objects.equals(m_root, other.m_root) && Objects.equals(m_type, other.m_type) &&
		// Objects.equals(m_name, other.m_name) &&
				Objects.equals(m_parents, other.m_parents);
	}

	public static RepositoryMetadata getInstance(final Path path) {
		return RepositoryMetadata.getInstance(path, null, null, null);
	}

	public static RepositoryMetadata getInstance(final Path path, final Class<? extends Repository> type) {
		return RepositoryMetadata.getInstance(path, type, null, null);
	}

	public static RepositoryMetadata getInstance(final Path path, final Class<? extends Repository> type, final Collection<Path> parentPaths, final Class<? extends Repository> parentType) {
		Class<? extends Repository> repoType = type;

		final Collection<Path> detectedParentPaths = new LinkedHashSet<>();
		if (parentPaths != null && parentPaths.size() > 0) {
			for (final Path parentPath : parentPaths) {
				detectedParentPaths.add(parentPath.normalize().toAbsolutePath());
			}
		}

		Class<? extends Repository> parentRepoType = parentType;
		try {
			final Map<String, String> metadata = Util.readMetadata(path);
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

			// use the parent path from the .metadata file, if found
			if (metadata.containsKey(METADATA_KEY_PARENTS)) {
				final String parents = metadata.get(METADATA_KEY_PARENTS);
				if (parents != null) {
					for (final String parent : parents.split(",")) {
						detectedParentPaths.add(path.resolve(Paths.get(parent)).normalize().toAbsolutePath());
					}
				}
			}

			// make sure we don't end up with ourself in the "parent" list
			detectedParentPaths.remove(path.normalize().toAbsolutePath());

			// get the parent type from a parent .metadata file, if found
			try {
				for (final Path detected : detectedParentPaths) {
					final File detectedFile = detected.toFile();
					if (detectedFile.exists() && detectedFile.isDirectory()) {
						final Map<String, String> parentMetadata = Util.readMetadata(detected);
						if (parentRepoType == null && parentMetadata.containsKey(METADATA_KEY_TYPE)) {
							final String typeValue = parentMetadata.get(METADATA_KEY_TYPE);
							parentRepoType = Class.forName(typeValue).asSubclass(Repository.class);
							break;
						}
					}
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

				final Set<RepositoryMetadata> parentMetadata = new LinkedHashSet<>();
				for (final Path detected : detectedParentPaths) {
					parentMetadata.add(RepositoryMetadata.getInstance(detected, parentRepoType));
				}
				return new RepositoryMetadata(path.normalize().toAbsolutePath(), repoType, name, lastIndexed, parentMetadata);
			}
		} catch (final IOException e) {
			LOG.warn("Failed to get instance of metadata for repository at {}", path);
			throw new RepositoryException(e);
		}
		throw new IllegalArgumentException("Path " + path + " is not a repository!");
	}

	@Override
	public int compareTo(final RepositoryMetadata o) {
		int ret = this.getRoot().compareTo(o.getRoot());
		if (ret == 0) {
			ret = this.getName().compareTo(o.getName());
		}
		if (ret == 0) {
			ret = Long.valueOf(o.getLastIndexed() - this.getLastIndexed()).intValue();
		}
		return ret;
	}
}
