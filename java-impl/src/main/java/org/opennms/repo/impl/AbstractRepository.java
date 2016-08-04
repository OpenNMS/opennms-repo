package org.opennms.repo.impl;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

import org.apache.commons.io.FileUtils;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.Util;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class AbstractRepository implements Repository {
	private static final RepositoryPackage[] EMPTY_REPOSITORY_PACKAGE_ARRAY = new RepositoryPackage[0];

	private static final Logger LOG = LoggerFactory.getLogger(AbstractRepository.class);

	private final RepositoryMetadata m_metadata;
	private final Repository m_parent;

	private Map<String, RepositoryPackage> m_packageCache = new HashMap<>();

	public AbstractRepository(final Path path) {
		this(path, null);
	}

	public AbstractRepository(final Path path, final Repository parent) {
		LOG.debug("Creating repository {}: path={}, parent={}", getClass().getSimpleName(), path, parent);
		if (parent == null) {
			m_metadata = RepositoryMetadata.getInstance(path, this.getClass(), null, null);
			LOG.trace("parent is null, using metadata: {}", m_metadata);
			if (m_metadata.hasParent()) {
				m_parent = m_metadata.getParentMetadata().getRepositoryInstance();
				LOG.trace("parent={}", m_parent);
			} else {
				LOG.trace("no parent from metadata");
				m_parent = null;
			}
		} else {
			m_metadata = RepositoryMetadata.getInstance(path, this.getClass(), parent.getRoot(), parent.getClass());
			LOG.trace("parent is not null, using metadata: {}", m_metadata);
			m_parent = parent;
		}
	}

	@Override
	public int hashCode() {
		return Objects.hash(m_metadata, m_parent);
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
		return Objects.equals(m_metadata, other.m_metadata) && Objects.equals(m_parent, other.m_parent);
	}

	@Override
	public Path getRoot() {
		return m_metadata.getRoot();
	}

	@Override
	public Repository getParent() {
		return m_parent;
	}

	@Override
	public boolean hasParent() {
		return m_parent != null && m_metadata.hasParent();
	}

	@Override
	public String getName() {
		return m_metadata.getName();
	}

	@Override
	public void setName(final String name) {
		m_metadata.setName(name);
		m_metadata.store();
	}

	/*
	 * public Map<String,String> getMetadata() { return m_metadata; }
	 * 
	 * public void setMetadata(final Map<String,String> metadata) { m_metadata =
	 * metadata; }
	 */

	@Override
	public Path relativePath(final RepositoryPackage p) {
		return getRoot().relativize(p.getPath());
	}

	protected RepositoryPackage getPackage(final String packageName) {
		return m_packageCache.get(packageName);
	}

	@Override
	public <T extends Repository> void addPackages(final T repository) {
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
					m_metadata.resetLastIndexed();
				} else {
					LOG.debug("NOT copying {} to {} ({} is newer)", pack, relativeTargetPath, existingPackage);
				}
			} catch (final IOException e) {
				throw new RepositoryException(e);
			}
		}
		m_metadata.store();
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
		final Map<String, RepositoryPackage> existing = new HashMap<>();
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
		return m_metadata.getLastIndexed();
	}

	protected void updateLastIndexed() {
		m_metadata.touchLastIndexed();
	}

	@Override
	public int compareTo(final Repository o) {
		int ret = getRoot().compareTo(o.getRoot());
		if (ret == 0) {
			ret = m_parent.compareTo(o.getParent());
		}
		return ret;
	}

	@Override
	public String toString() {
		return getClass().getSimpleName() + "@" + System.identityHashCode(this) + ":" + getName() + "(parent="
				+ hasParent() + "):" + getRoot();
	}

	public void updateMetadata() {
		m_metadata.store();
	}

	@Override
	public <T extends Repository> T as(final Class<T> repository) {
		return repository.cast(this);
	}
}
