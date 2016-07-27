package org.opennms.repo.impl;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collection;
import java.util.stream.Collectors;

import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.impl.rpm.RPMRepository;

public abstract class RepoUtils {
    private RepoUtils() {}
    
    public static Collection<Repository> findRepositories(final Path path) {
        try {
            return Files.walk(path).filter(p -> {
                if (p.toFile().isDirectory()) {
                    final RPMRepository repo = new RPMRepository(p);
                    return repo.isValid();
                }
                return false;
            }).map(p -> {
                try {
                    return new RPMRepository(p);
                } catch (final Exception e) {
                    return null;
                }
            }).sorted().collect(Collectors.toList());
        } catch (final IOException e) {
            throw new RepositoryException(e);
        }
    }
}
