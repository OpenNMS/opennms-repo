package org.opennms.repo.impl;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.FileTime;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.SortedSet;
import java.util.TreeSet;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.opennms.repo.api.Filter;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.RepositoryPackage.Architecture;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.rpm.DeltaRPM;
import org.opennms.repo.impl.rpm.RPMPackage;
import org.opennms.repo.impl.rpm.RPMUtils;
import org.opennms.repo.impl.rpm.RepoSetComparator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class AbstractRepository implements Repository {
	private static final RepositoryPackage[] EMPTY_REPOSITORY_PACKAGE_ARRAY = new RepositoryPackage[0];
	private static final RepoSetComparator REPO_SET_COMPARATOR = new RepoSetComparator();

	private static final Logger LOG = LoggerFactory.getLogger(AbstractRepository.class);

	private final RepositoryMetadata m_metadata;
	private final SortedSet<Repository> m_parents;

	private Map<String, RepositoryPackage> m_packageCache = new HashMap<>();

	public AbstractRepository(final Path path) {
		this(path, null);
	}

	public AbstractRepository(final Path path, final SortedSet<Repository> parents) {
		LOG.debug("Creating repository {}: path={}, parents={}", getClass().getSimpleName(), path, parents);
		if (parents == null || parents.size() == 0) {
			m_metadata = RepositoryMetadata.getInstance(path, this.getClass(), null, null);
			LOG.trace("parent is null, using metadata: {}", m_metadata);
			if (m_metadata.hasParent()) {
				m_parents = new TreeSet<>(Util.getStream(m_metadata.getParentMetadata()).map(parent -> {
					return parent.getRepositoryInstance();
				}).collect(Collectors.toList()));
				LOG.trace("parents={}", m_parents);
			} else {
				LOG.trace("no parent from metadata");
				m_parents = new TreeSet<>();
			}
		} else {
			m_metadata = RepositoryMetadata.getInstance(path, this.getClass(), Util.getStream(parents).map(parent -> {
				return parent.getRoot();
			}).collect(Collectors.toList()), parents.iterator().next().getClass());
			LOG.trace("parent is not null, using metadata: {}", m_metadata);
			m_parents = parents;
		}
	}

	@Override
	public RepositoryMetadata getMetadata() {
		return m_metadata;
	}

	@Override
	public int hashCode() {
		return Objects.hash(m_metadata, m_parents);
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
		return Objects.equals(m_metadata, other.m_metadata) && Objects.equals(m_parents, other.m_parents);
	}

	@Override
	public Path getRoot() {
		return m_metadata.getRoot();
	}

	@Override
	public SortedSet<Repository> getParents() {
		return m_parents;
	}

	@Override
	public boolean hasParent() {
		return m_parents != null && m_parents.size() > 0;
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

	@Override
	public Path relativePath(final RepositoryPackage p) {
		return getRoot().relativize(p.getPath().toAbsolutePath());
	}

	protected RepositoryPackage getPackage(final String packageUniqueName) {
		return m_packageCache.get(packageUniqueName);
	}

	@Override
	public <T extends Repository> void addPackages(final T repository, final Filter... filters) {
		LOG.debug("addPackages({})", repository);
		repository.refresh();
		final Collection<RepositoryPackage> fromPackages = repository.getPackages().stream().filter(Util.combineFilters(filters)).collect(Collectors.toList());

		LOG.info("Adding new packages from {} to repository {}", repository, this);
		addPackages(fromPackages.toArray(EMPTY_REPOSITORY_PACKAGE_ARRAY));
	}

	/**
	 * Given a package, return the ideal path for that package.
	 * 
	 * @param pack
	 *            the package
	 * @return the normalized/ideal path to the package (including filename)
	 */
	protected abstract Path getIdealPath(final RepositoryPackage pack);

	@Override
	public void normalize() throws RepositoryException {
		refresh();
		Util.getStream(getPackages()).forEach(pack -> {
			final Path existingPath = pack.getPath().normalize().toAbsolutePath();
			final Path idealPath = getIdealPath(pack);
			if (!existingPath.equals(idealPath)) {
				if (LOG.isDebugEnabled()) {
					LOG.debug("normalize: moving {} to {}", Util.relativize(existingPath), Util.relativize(idealPath));
				}
				try {
					Files.createDirectories(idealPath.getParent());
					Files.move(existingPath, idealPath, StandardCopyOption.REPLACE_EXISTING);
				} catch (final IOException e) {
					throw new RepositoryException("Failed to move " + existingPath + " to " + idealPath);
				}
			}
		});
	}

	@Override
	public void addPackages(final RepositoryPackage... packages) {
		LOG.debug("addPackages: {}", Arrays.asList(packages));
		refresh();
		for (final RepositoryPackage pack : packages) {
			try {
				final Path targetPath = getIdealPath(pack);
				final Path relativeTargetPath = Util.relativize(targetPath);
				final RepositoryPackage existingPackage = getPackage(pack.getUniqueName());
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

				if (existingPackage != null) {
					final Architecture newArch = pack.getArchitecture();
					final Architecture existingArch = pack.getArchitecture();
					if (newArch != null && existingArch != null && !existingArch.equals(newArch)) {
						LOG.warn("{} and {} do not have the same architecture; skipping delta generation.", existingPackage, pack);
					} else if (pack.getVersion().equals(existingPackage.getVersion())) {
						LOG.warn("{} and {} are the same version); skipping delta generation.", pack, existingPackage);
					} else if (Architecture.SOURCE.equals(pack.getArchitecture()) || Architecture.SOURCE.equals(existingPackage.getArchitecture())) {
						LOG.debug("Skipping source RPM {}", pack);
					} else {
						LOG.debug("making delta RPM from {} ({}) and {} ({})", Util.relativize(pack.getPath()), newArch, Util.relativize(existingPackage.getPath()), existingArch);
						final DeltaRPM drpm = new DeltaRPM((RPMPackage) pack, (RPMPackage) existingPackage);
						final Path drpmPath = getRoot().resolve("drpms");
						final File drpmFile = drpm.getFilePath(drpmPath).toFile();
						if (drpmFile.exists()) {
							LOG.debug("Delta RPM for {} -> {} already exists.", pack, existingPackage);
						} else {
							LOG.debug("Delta RPM for {} -> {} does NOT already exist.", pack, existingPackage);
							try {
								RPMUtils.generateDelta(pack.getFile(), pack.getFile(), drpmFile);
								m_metadata.resetLastIndexed();
							} catch (final Exception e) {
								LOG.warn("Failed to generate delta RPM: {} -> {}", Util.relativize(pack.getPath()), Util.relativize(existingPackage.getPath()), e);
							}
						}
					}
				}
			} catch (final IOException e) {
				throw new RepositoryException(e);
			}
		}
		m_metadata.store();
	}

	protected void updatePackage(final RepositoryPackage pack) {
		m_packageCache.put(pack.getUniqueName(), pack);
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
		LOG.info("Refreshing {}", this);
		final Map<String, RepositoryPackage> existingPackagesByName = new HashMap<>();
		Util.getStream(getPackages()).forEach(pack -> {
			final String uniqueName = pack.getUniqueName();
			final RepositoryPackage newestPackage = existingPackagesByName.get(uniqueName);
			if (newestPackage == null || newestPackage.isLowerThan(pack)) {
				existingPackagesByName.put(uniqueName, pack);
			}
		});
		LOG.debug("{} packages: {}", this, existingPackagesByName);
		m_packageCache = existingPackagesByName;
		updateMetadata();
	}

	@Override
	public boolean index() throws RepositoryIndexException {
		return index(null);
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
			ret = REPO_SET_COMPARATOR.compare(m_parents, o.getParents());
		}
		return ret;
	}

	@Override
	public String toString() {
		return getRepositoryTypeName() + " repository '" + getName() + "' at " + Util.relativize(getRoot());
	}

	public void updateMetadata() {
		m_metadata.store();
	}

	protected abstract String getRepositoryTypeName();

	@Override
	public <T extends Repository> T as(final Class<T> repository) {
		return repository.cast(this);
	}
}
