package org.opennms.repo.impl;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collection;
import java.util.SortedSet;
import java.util.UUID;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.rpm.RPMRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class RepoUtils {
	private static final Logger LOG = LoggerFactory.getLogger(RepoUtils.class);

	private RepoUtils() {
	}

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
		} catch (final IOException e) {
			LOG.error("Failed to clean up directory {}", toPath, e);
			throw new RuntimeException(e);
		}

		try {
			final RsyncCommand rsync = new RsyncCommand(from, to);
			rsync.run();
			return;
		} catch (final Exception e) {
			LOG.debug("`rsync` not found or rsync failed", e);
		}

		// if rsync fails
		LOG.debug("Using NIO to clone {}", Util.relativize(fromPath));
		try {
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

	public static void rename(final Path from, final Path to) {
		LOG.debug("Replacing path {} with path {} atomically", to, from);
		final Path deleteMe = from.getParent().resolve(".delete-me-repo-" + UUID.randomUUID());

		Path target = to;
		while (Files.isSymbolicLink(target)) {
			try {
				target = Files.readSymbolicLink(target);
			} catch (final IOException e) {
				throw new RepositoryException("Unable to resolve symlink " + target, e);
			}
		}

		try {
			if (target.toFile().exists()) {
				FileUtils.moveDirectory(target.toFile(), deleteMe.toFile());
			}
			FileUtils.moveDirectory(from.toFile(), target.toFile());
		} catch (final IOException e) {
			LOG.error("Failed to replace repository {} with {}", from, target, e);
			throw new RepositoryException("Failed to replace repository " + from + " with " + target, e);
		} finally {
			FileUtils.deleteQuietly(deleteMe.toFile());
		}
	}

	public static void delete(final Path file) throws RepositoryException {
		try {
			FileUtils.forceDelete(file.toFile());
		} catch (final IOException e) {
			LOG.error("Failed to forcibly delete file {}", file, e);
			throw new RepositoryException("Failed to delete file " + file, e);
		}
	}

	public static void copyFile(final Path from, final Path to) throws RepositoryException {
		if (from.toFile().isDirectory()) {
			throw new IllegalArgumentException("Util.copyFile() 'from' should be a file, not a directory!");
		}
		Path source = from.normalize().toAbsolutePath();
		Path target = to.normalize().toAbsolutePath();
		String filename = to.getFileName().toString();
		if (to.toFile().isDirectory()) {
			filename = from.getFileName().toString();
			target = target.resolve(filename);
		}
		Path temp = null;
		try {
			Files.createDirectories(target.getParent());
			temp = Files.createTempFile(target.getParent(), "repo", ".tmp");
			temp.toFile().delete();
			while (Files.isSymbolicLink(source)) {
				source = Files.readSymbolicLink(source);
			}
			Files.createLink(temp, source);
			RepoUtils.rename(from, target);
		} catch (final IOException e) {
			LOG.debug("Failed to copy {} to {}", from, to, e);
			throw new RepositoryException("Failed to copy " + from + " to " + to, e);
		} finally {
			if (temp != null) {
				temp.toFile().delete();
			}
		}
	}

	public static void touch(final Path file) throws RepositoryException {
		try {
			FileUtils.touch(file.toFile());
		} catch (final IOException e) {
			LOG.debug("Failed to touch {}", file, e);
			throw new RepositoryException("Failed to touch file " + file, e);
		}
	}

	public static Repository createTempRepository(final Repository repo) {
		try {
			final Path tempPath = Files.createTempDirectory(repo.getRoot().getParent(), ".temp-repo-");
			repo.refresh();
			final SortedSet<Repository> parents = repo.getParents();
			LOG.debug("createTempRepository: {} -> {} (parents={})", repo, tempPath, parents);

			RepoUtils.cloneDirectory(repo.getRoot(), tempPath);
			final RepositoryMetadata newMetadata;
			if (parents == null || parents.size() == 0) {
				newMetadata = RepositoryMetadata.getInstance(tempPath, repo.getClass(), null, null);
			} else {
				newMetadata = RepositoryMetadata.getInstance(tempPath, repo.getClass(), parents.parallelStream().sorted().distinct().map(parent -> {
					return parent.getRoot();
				}).sorted().distinct().collect(Collectors.toList()), parents.first().getClass());
			}
			LOG.debug("createTempRepository: new metadata={}", newMetadata);
			newMetadata.store();
			return newMetadata.getRepositoryInstance();
		} catch (final IOException e) {
			LOG.warn("Failed to create temporary repository from {}", repo);
			throw new RepositoryException("Failed to create temporary repository from " + repo, e);
		}
	}
}
