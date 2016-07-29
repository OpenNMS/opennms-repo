package org.opennms.repo.api;

import java.util.Collection;

public interface MetaRepository extends Repository {
	/**
	 * Add packages to the specified sub-repository from the given source repository.
	 * The sub-repository must also exist on the source repository.
	 * @param subrepo the sub-repository name
	 * @param source the source repository to copy from
	 */
	public void addPackages(final String subrepo, final Repository source);
	
	/**
	 * Add packages to the specified sub-repository.
	 * @param subrepo the sub-repository name
	 * @param packages the packages to add
	 */
	public void addPackages(final String subrepo, final RepositoryPackage... packages);

	/**
	 * Retrieve the specified sub-repository.
	 * @param subrepo the sub-repository name
	 */
	public Repository getSubRepository(final String subrepo);
	
	/**
	 * Retrieve all sub-repositories in this meta-repository.
	 * @return a collection of {@link Repository} objects
	 */
	public Collection<Repository> getSubRepositories();
}
