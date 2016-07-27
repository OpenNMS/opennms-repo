package org.opennms.repo.api;

import java.nio.file.Path;
import java.util.Collection;

public interface Repository extends Comparable<Repository> {
    public static final String REPO_METADATA_FILENAME = ".repometa";
    /**
     * Get the root path of the repository.
     * @return The repository root as a {@link Path}.
     */
    public Path getRoot();

    /**
     * Get the repository's parent.
     * @return the parent {@link Repository}
     */
    public Repository getParent();

    /**
     * Get the repository's display name.
     * @return the name
     */
    public String getName();

    /**
     * Set the repository's display name.
     * @param name the name
     */
    public void setName(final String name);

    /**
     * Whether or not the repository exists and is valid.
     * @return true or false
     */
    public boolean isValid();

    /**
     * Generate/update indexes for the repository without signing them.
     */
    public void index() throws RepositoryIndexException;

    /**
     * Generate/update indexes for the repository.
     * @param gpginfo the GPG key and identity info
     */
    public void index(final GPGInfo gpginfo) throws RepositoryIndexException;

    /**
     * Get the complete list of packages in the repository.
     * @return a collection of {@link RepositoryPackage} objects.
     */
    public Collection<RepositoryPackage> getPackages();

    /**
     * Get the relative path to a package from the repository root.
     * @param pack the package
     * @return the path
     */
    public Path relativePath(RepositoryPackage pack);

    /**
     * Sync new packages from the specified repository into the current repository.
     * This should only copy packages that are newer than any current version in
     * the repository.
     * @param repository the repository to sync from
     */
    public<T extends Repository> void addPackages(T repository);

    /**
     * Copy the contents of a repository into a new directory.  If the directory has
     * existing files, they will be removed.
     * @param path the path to clone to
     * @return the new repository
     */
    public Repository cloneInto(Path path);
}
