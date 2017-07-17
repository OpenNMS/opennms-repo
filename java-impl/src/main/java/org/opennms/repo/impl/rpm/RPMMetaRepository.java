package org.opennms.repo.impl.rpm;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.SortedSet;
import java.util.TreeSet;
import java.util.concurrent.ConcurrentSkipListMap;
import java.util.stream.Collectors;

import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.MetaRepository;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.AbstractRepository;
import org.opennms.repo.impl.RepoUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMMetaRepository extends AbstractRepository implements MetaRepository {
	private static final Logger LOG = LoggerFactory.getLogger(RPMMetaRepository.class);
	private static final RepoSetComparator REPOSET_COMPARATOR = new RepoSetComparator();

	private Map<String, RPMRepository> m_subRepositories = new ConcurrentSkipListMap<>();

	public RPMMetaRepository(final Path root) {
		super(root);
	}

	public RPMMetaRepository(final Path root, final SortedSet<Repository> parents) {
		super(root, parents);
	}

	@Override
	public boolean isValid() {
		if (!getRoot().toFile().exists()) {
			return false;
		}
		return getRoot().resolve("common").resolve("repodata").resolve("repomd.xml").toFile().exists() && getRoot().resolve(REPO_METADATA_FILENAME).toFile().exists();
	}

	protected void ensureSubrepositoryExists(final Path subrepoPath, final GPGInfo gpginfo) {
		final String subrepoName = subrepoPath.getFileName().toString();

		if (subrepoPath.toFile().exists() && subrepoPath.resolve(REPO_METADATA_FILENAME).toFile().exists()) {
			LOG.debug("{} sub-repository already exists in {}.", subrepoName, this);
		} else {
			LOG.debug("{} sub-repository does not exist in {}.  Initializing.", subrepoName, this);
			final SortedSet<Repository> parentSubRepositories = getSubRepositoryParents(subrepoName);
			final RPMRepository subrepo = new RPMRepository(subrepoPath, parentSubRepositories);
			LOG.debug("parent={}, {}={}", parentSubRepositories, subrepoName, subrepo);
			subrepo.index(gpginfo);
		}
	}

	protected void ensureSubrepositoriesExist(final GPGInfo gpginfo) {
		try {
			Files.createDirectories(getRoot());
			final Set<Path> subrepos = new HashSet<>(Files.list(getRoot()).filter(path -> {
				return path.toFile().exists() && path.toFile().isDirectory();
				// return path.toFile().exists() &&
				// path.resolve(REPO_METADATA_FILENAME).toFile().exists();
			}).map(path -> {
				return path.normalize().toAbsolutePath();
			}).collect(Collectors.toSet()));
			subrepos.add(getRoot().resolve("common"));
			LOG.debug("ensuring sub repositories exist: {}", subrepos);
			Util.getStream(subrepos).forEach(subrepository -> {
				ensureSubrepositoryExists(subrepository, gpginfo);
			});
		} catch (final IOException e) {
			throw new RepositoryException("Failed to list subrepositories in " + getRoot(), e);
		}
	}

	@Override
	protected Path getIdealPath(final RepositoryPackage pack) {
		return pack.getPath();
	}

	@Override
	public void normalize() throws RepositoryException {
		final Collection<Repository> subRepositories = getSubRepositories(true);
		LOG.debug("normalize(): subrepositories={}", subRepositories);
		Util.getStream(subRepositories).forEach(repo -> {
			repo.normalize();
		});
	}

	@Override
	public boolean index(final GPGInfo gpginfo) throws RepositoryIndexException {
		LOG.debug("index");
		ensureSubrepositoriesExist(gpginfo);
		if (hasParent()) {
			Util.getStream(getParents()).forEach(parent -> {
				parent.as(RPMMetaRepository.class).ensureSubrepositoriesExist(gpginfo);
			});
		}
		final boolean changed = Util.getStream(getSubRepositories()).anyMatch(repo -> {
			LOG.debug("indexing: {}", repo);
			return repo.index(gpginfo);
		});

		updateLastIndexed();
		updateMetadata();
		return changed;
	}

	@Override
	public void refresh() {
		final Collection<Repository> subrepos = getSubRepositories();
		LOG.debug("Refreshing sub-repositories: {}", subrepos);
		Util.getStream(subrepos).forEach(repo -> {
			repo.refresh();
		});
	}

	public Repository getSubRepository(final String subrepo) {
		return getSubRepository(subrepo, false);
	}

	/**
	 * Get the sub-repository with the given repo name. For example,
	 * getSubRepository("common") will get the RPM repository in the "common"
	 * subdirectory inside this meta repository.
	 * 
	 * @param subRepoName
	 *            the name of the sub-repository
	 * @return the matching RPMRepository, if it exists and is valid
	 */
	protected RPMRepository getSubRepository(final String subRepoName, final boolean create) {
		LOG.debug("getSubRepository: {}", subRepoName);
		if (m_subRepositories.containsKey(subRepoName)) {
			return m_subRepositories.get(subRepoName);
		}
		final Path repositoryPath = getRoot().resolve(subRepoName);
		if (create || !repositoryPath.toFile().exists() || repositoryPath.resolve(REPO_METADATA_FILENAME).toFile().exists()) {
			final SortedSet<Repository> parentRepos = getSubRepositoryParents(subRepoName);
			final RPMRepository repo = new RPMRepository(repositoryPath, parentRepos);
			LOG.debug("getSubRepository: found {}", repo);
			if (repo.isValid() || create) {
				m_subRepositories.put(repo.getName(), repo);
				return repo;
			}
		}
		return null;
	}

	private SortedSet<Repository> getSubRepositoryParents(final String subRepoName) {
		if (getParents() == null || getParents().size() == 0) {
			return Collections.emptySortedSet();
		}
		return new TreeSet<>(Util.getStream(getParents()).map(parent -> {
			return parent.as(RPMMetaRepository.class).getSubRepository(subRepoName, false);
		}).collect(Collectors.toList()));
	}

	@Override
	public Collection<RepositoryPackage> getPackages() {
		final List<RepositoryPackage> packages = new ArrayList<>();
		for (final Repository repository : getSubRepositories()) {
			packages.addAll(repository.getPackages());
		}
		return packages;
	}

	@Override
	public Collection<Repository> getSubRepositories() {
		return getSubRepositories(true);
	}

	private Collection<Repository> getSubRepositories(final Boolean index) {
		if (index == null || index) {
			ensureSubrepositoriesExist(null);
		}
		try {
			final SortedSet<Repository> parents = getParents();
			return Files.list(getRoot()).filter(path -> {
				return path.toFile().isDirectory() && !Files.isSymbolicLink(path) && path.resolve(REPO_METADATA_FILENAME).toFile().exists();
			}).map(path -> {
				final String repoName = path.getFileName().toString();
				final RPMRepository existing = m_subRepositories.get(repoName);
				if (existing != null) {
					if (!hasParent()) {
						// we don't have a parent, so we shouldn't expect the
						// sub-repo to have one
						return existing;
					}
					if (existing.hasParent()) {
						return existing;
					}
					// existing doesn't have a parent, but we do...
					// fall through to recreating the sub-repository just
					// to be sure we get a parent, if possible
				}
				final SortedSet<Repository> subParents = new TreeSet<>(Util.getStream(parents).map(parent -> {
					return parent.as(RPMMetaRepository.class).getSubRepository(repoName, false);
				}).collect(Collectors.toList()));
				final RPMRepository repo = new RPMRepository(path, subParents);
				m_subRepositories.put(repoName, repo);
				return repo;
			}).collect(Collectors.toList());
		} catch (final IOException e) {
			throw new RepositoryIndexException("Failed to find scan " + this.toString() + " for sub-repositories.", e);
		}
	}

	@Override
	public <T extends Repository> void addPackages(T repository) {
		repository.refresh();
		this.refresh();
		final RPMRepository repo = getSubRepository("common", true);
		if (repository instanceof RPMMetaRepository) {
			final RPMMetaRepository other = repository.as(RPMMetaRepository.class);
			final RPMRepository common = other.getSubRepository("common", false);
			if (common == null) {
				LOG.warn("Attempting to add packages from a missing sub-repository!");
			} else {
				repo.addPackages(common);
			}
		} else {
			repo.addPackages(repository);
		}
	}

	@Override
	public void addPackages(final String subrepo, final Repository repository) {
		final RPMRepository to = getSubRepository(subrepo, true);
		final Repository from;
		if (repository instanceof RPMMetaRepository) {
			from = ((RPMMetaRepository) repository).getSubRepository(subrepo, true);
		} else if (repository instanceof RPMRepository) {
			from = repository;
		} else {
			throw new RepositoryException("Repository must be an RPM meta repository with a matching subrepo, or an RPM repository!");
		}
		// LOG.debug("from = {}, to = {}", from, to);
		to.addPackages(from);
	}

	@Override
	public void addPackages(final RepositoryPackage... packages) {
		refresh();
		final RPMRepository subRepo = getSubRepository("common", true);
		subRepo.addPackages(packages);
	}

	@Override
	public void addPackages(final String subrepo, final RepositoryPackage... packages) {
		final RPMRepository repo = getSubRepository(subrepo, true);
		repo.addPackages(packages);
	}

	@Override
	public Repository cloneInto(final Path to) {
		final Path from = getRoot().normalize().toAbsolutePath();
		RepoUtils.cloneDirectory(from, to);
		final SortedSet<Repository> repos = new TreeSet<>();
		repos.add(this);
		return new RPMMetaRepository(to, repos);
	}

	@Override
	public int compareTo(final Repository o) {
		if (o instanceof RPMMetaRepository) {
			final RPMMetaRepository other = (RPMMetaRepository) o;
			final SortedSet<Repository> myRepositories = new TreeSet<>(getSubRepositories());
			final SortedSet<Repository> otherRepositories = new TreeSet<>(other.getSubRepositories());
			return REPOSET_COMPARATOR.compare(myRepositories, otherRepositories);
		}
		return -1;
	}

	@Override
	protected String getRepositoryTypeName() {
		return "RPM container";
	}
}
