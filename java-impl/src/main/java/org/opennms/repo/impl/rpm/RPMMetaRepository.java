package org.opennms.repo.impl.rpm;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
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
import org.opennms.repo.impl.AbstractRepository;
import org.opennms.repo.impl.RepoUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMMetaRepository extends AbstractRepository implements MetaRepository {
    private static final Logger LOG = LoggerFactory.getLogger(RPMMetaRepository.class);
    private static final RepoSetComparator REPOSET_COMPARATOR = new RepoSetComparator();

    private Map<String,RPMRepository> m_subRepositories = new ConcurrentSkipListMap<>();

    public RPMMetaRepository(final Path root) {
        super(root);
    }

    public RPMMetaRepository(final Path root, final Repository parent) {
        super(root, parent);
    }

    @Override
    public boolean isValid() {
        if (!getRoot().toFile().exists()) {
            return false;
        }
        return getRoot().resolve("common").resolve("repodata").resolve("repomd.xml").toFile().exists() &&
                getRoot().resolve(REPO_METADATA_FILENAME).toFile().exists();
    }

    protected void ensureCommonRepositoryExists(final GPGInfo gpginfo) {
        final Path commonPath = getRoot().resolve("common");
        if (commonPath.toFile().exists() && commonPath.resolve(REPO_METADATA_FILENAME).toFile().exists()) {
        	LOG.debug("Common sub-repository already exists.");
        } else {
            LOG.debug("Common sub-repository does not exist in {}.  Initializing.", this);
            final RPMRepository parentSubRepository = getSubRepositoryParent("common");
            final RPMRepository commonRepository = new RPMRepository(commonPath, parentSubRepository);
            LOG.debug("parent={}, common={}", parentSubRepository, commonRepository);
            commonRepository.index(gpginfo);
        }
    }

    @Override
    public void index(final GPGInfo gpginfo) throws RepositoryIndexException {
    	LOG.debug("index");
    	ensureCommonRepositoryExists(gpginfo);
    	if (hasParent()) {
    		RPMMetaRepository parent = getParent().as(RPMMetaRepository.class);
    		parent.ensureCommonRepositoryExists(gpginfo);
    	}
        getSubRepositories().forEach(repo -> {
        	LOG.debug("indexing: {}", repo);
        	repo.index(gpginfo);
        });
        updateLastIndexed();
        updateMetadata();
    }

    @Override
    public void refresh() {
    	final Collection<Repository> subrepos = getSubRepositories();
    	LOG.debug("Refreshing sub-repositories: {}", subrepos);
		subrepos.stream().forEach(repo -> {
    		repo.refresh();
    	});
    }

    public Repository getSubRepository(final String subrepo) {
    	return getSubRepository(subrepo, false);
    }

    /**
     * Get the sub-repository with the given repo name.
     * For example, getSubRepository("common") will get the RPM repository
     * in the "common" subdirectory inside this meta repository.
     * @param subRepoName the name of the sub-repository
     * @return the matching RPMRepository, if it exists and is valid
     */
    protected RPMRepository getSubRepository(final String subRepoName, final boolean create) {
        LOG.debug("getSubRepository: {}", subRepoName);
        if (m_subRepositories.containsKey(subRepoName)) {
        	return m_subRepositories.get(subRepoName);
        }
        final Path repositoryPath = getRoot().resolve(subRepoName);
        if (create || !repositoryPath.toFile().exists() || repositoryPath.resolve(REPO_METADATA_FILENAME).toFile().exists()) {
            final RPMRepository parentRepo = getSubRepositoryParent(subRepoName);
            final RPMRepository repo = new RPMRepository(repositoryPath, parentRepo);
            LOG.debug("getSubRepository: found {}", repo);
            if (repo.isValid() || create) {
            	m_subRepositories.put(repo.getName(), repo);
                return repo;
            }
        }
        return null;
    }

    private RPMRepository getSubRepositoryParent(final String subRepoName) {
        if (getParent() == null) {
            return null;
        }
        return getParent().as(RPMMetaRepository.class).getSubRepository(subRepoName, false);
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
        try {
        	ensureCommonRepositoryExists(null);
            final RPMMetaRepository parent = getParent() == null? null : getParent().as(RPMMetaRepository.class);
            return Files.list(getRoot()).filter(path -> {
            	return path.toFile().isDirectory() && path.resolve(REPO_METADATA_FILENAME).toFile().exists();
            }).map(path -> {
                final String repoName = path.getFileName().toString();
                final RPMRepository existing = m_subRepositories.get(repoName);
                if (existing != null) {
                	if (!hasParent()) {
                		// we don't have a parent, so we shouldn't expect the sub-repo to have one
                		return existing;
                	}
                	if (existing.hasParent()) {
                		return existing;
                	}
                	// existing doesn't have a parent, but we do...
                	// fall through to recreating the sub-repository just
                	// to be sure we get a parent, if possible
                }
                final RPMRepository parentSubRepository = parent == null? null : parent.getSubRepository(repoName, false);
            	final RPMRepository repo = new RPMRepository(path, parentSubRepository);
            	m_subRepositories.put(repoName, repo);
            	return repo;
            }).collect(Collectors.toList());
        } catch (final IOException e) {
            throw new RepositoryIndexException("Failed to find scan " + this.toString() + " for sub-repositories.", e);
        }
    }

    @Override
    public Path relativePath(RepositoryPackage pack) {
        // TODO Auto-generated method stub
        throw new UnsupportedOperationException("Not yet implemented!");
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
    	//LOG.debug("from = {}, to = {}", from, to);
    	to.addPackages(from);
    }

    @Override
    public void addPackages(final RepositoryPackage... packages) {
    	refresh();
        final RPMRepository subRepo = getSubRepository("common", true);
        subRepo.addPackages(packages);
    }

    @Override
    public void addPackages(final String subrepo, final RepositoryPackage...packages) {
    	final RPMRepository repo = getSubRepository(subrepo, true);
    	repo.addPackages(packages);
    }

    @Override
    public Repository cloneInto(final Path to) {
		final Path from = getRoot().normalize().toAbsolutePath();
		RepoUtils.cloneDirectory(from, to);
		return new RPMMetaRepository(to, this);
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
}
