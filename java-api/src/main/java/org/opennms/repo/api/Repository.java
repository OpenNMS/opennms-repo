package org.opennms.repo.api;

import java.nio.file.Path;

public interface Repository {
    /**
     * Get the root path of the repository.
     * @return The repository root as a {@link Path}.
     */
    public Path getRoot();
    
    /**
     * Whether or not the repository exists.
     * @return true or false
     */
    public boolean exists();
    
    /**
     * Generate/update indexes for the repository.
     */
    public void index(final GPGInfo gpginfo) throws RepositoryIndexException;
}
