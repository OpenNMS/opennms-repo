package org.opennms.repo.impl;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collection;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.rpm.RPMRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class RepoUtils {
	private static final Logger LOG = LoggerFactory.getLogger(RepoUtils.class);

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

    public static boolean isMetadata(final Path p) {
    	return p.getFileName().toString().equals(Repository.REPO_METADATA_FILENAME);
    }

	public static void cloneDirectory(final Path from, final Path to) {
		final Path fromPath = from.normalize().toAbsolutePath();
		final Path toPath = to.normalize().toAbsolutePath();
		LOG.info("Cloning from {} into {}", Util.relativize(fromPath), toPath);
		try {
			FileUtils.cleanDirectory(toPath.toFile());
			Files.walk(fromPath).filter(p -> {
				return !RepoUtils.isMetadata(p);
			}).forEach(p -> {
				try {
					final Path relativePath = fromPath.relativize(p);
					final Path targetPath = toPath.resolve(relativePath).normalize();
					if (p.toFile().isDirectory()) {
						LOG.debug("clone: creating directory {}", Util.relativize(targetPath));
						Files.createDirectories(targetPath);
					} else {
						LOG.debug("clone: Copying {} to {}", Util.relativize(p), Util.relativize(targetPath));
						Files.createLink(targetPath, p);
					}
				} catch (final IOException e) {
					throw new RepositoryException(e);
				}
			});
		} catch (final IOException e) {
			throw new RepositoryException(e);
		}
	}
}
