package org.opennms.repo.impl.rpm;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.FileTime;
import java.util.Collection;
import java.util.Collections;
import java.util.Optional;
import java.util.SortedSet;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.AbstractRepository;
import org.opennms.repo.impl.GPGUtils;
import org.opennms.repo.impl.RepoUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RPMRepository extends AbstractRepository {
	private static final Logger LOG = LoggerFactory.getLogger(RPMRepository.class);
	private static final Pattern DRPM = Pattern.compile("^(.*?)-(?:(\\d+)\\:)?([^-]+)-([^_]+)_(?:(\\d+)\\:)?([^-]+)-([^_]+)\\.([^\\.]+)\\.drpm$");

	public RPMRepository(final Path path) {
		super(path);
	}

	public RPMRepository(final Path path, final SortedSet<Repository> parents) {
		super(path, parents);
	}

	@Override
	public Collection<RepositoryPackage> getPackages() {
		final Path root = getRoot();
		if (!root.toFile().exists() || !root.toFile().isDirectory()) {
			return Collections.emptyList();
		}

		try {
			return Files.walk(root).filter(path -> {
				return path.toString().endsWith(".rpm") && path.toFile().isFile();
			}).map(path -> {
				try {
					return RPMUtils.getPackage(path.toFile());
				} catch (final Exception e) {
					LOG.warn("Failed to get package for path {}", path);
					return null;
				}
			}).filter(p -> p != null).sorted().collect(Collectors.toList());
		} catch (final IOException e) {
			throw new RepositoryException("Unable to walk " + root + " directory for RPMs", e);
		}
	}

	@Override
	public boolean isValid() {
		if (!getRoot().toFile().exists()) {
			return false;
		}
		return getRoot().resolve("repodata").resolve("repomd.xml").toFile().exists() && getRoot().resolve(REPO_METADATA_FILENAME).toFile().exists();
	}

	private void ensureRootExists() {
		final Path root = getRoot();
		try {
			if (!root.toFile().exists()) {
				Files.createDirectories(root);
			}
		} catch (final Exception e) {
			throw new RepositoryIndexException("Unable to create repository root '" + root + "'!", e);
		}
		updateMetadata();
	}

	@Override
	protected Path getIdealPath(final RepositoryPackage pack) {
		Path targetDirectory = this.getRoot().normalize().toAbsolutePath().resolve("rpms").resolve(pack.getCollationName());
		if (pack.getArchitecture() != null) {
			String archString;
			switch (pack.getArchitecture()) {
			case I386:
				archString = "i386";
				break;
			case AMD64:
				archString = "x86_64";
				break;
			case ALL:
				archString = "noarch";
				break;
			case SOURCE:
				archString = "source";
				break;
			default:
				archString = "misc";
				break;
			}
			targetDirectory = targetDirectory.resolve(archString);
		}
		return targetDirectory.resolve(pack.getPath().getFileName());
	}

	@Override
	public boolean index(final GPGInfo gpginfo) throws RepositoryIndexException {
		final Path root = getRoot();
		ensureRootExists();

		if (hasParent()) {
			for (final Repository repo : getParents()) {
				addPackages(repo);
			}
		} else {
			LOG.trace("No parent {}", this);
		}

		refresh();

		if (!isDirty()) {
			LOG.info("{} is unchanged.", this);
			return false;
		}

		ensureRootExists();
		generateDeltas();
		cleanUpDeltas();

		LOG.info("Indexing {}", this);
		final CreaterepoCommand command = new CreaterepoCommand(root);
		command.run();
		final Path repomdfile = root.resolve("repodata").resolve("repomd.xml");

		if (gpginfo == null) {
			LOG.warn("Skipping repomd.xml signing!");
		} else {
			final String ascPath = repomdfile.toString() + ".asc";
			final String keyPath = repomdfile.toString() + ".key";

			try {
				final Path signfile = Paths.get(ascPath);
				GPGUtils.detach_sign(repomdfile, signfile, gpginfo, false);
			} catch (final InterruptedException | IOException e) {
				LOG.debug("Failed to detach-sign {}", repomdfile, e);
				throw new RepositoryException(e);
			}

			final Path keyfile = Paths.get(keyPath);
			try {
				GPGUtils.exportKeyRing(keyfile, gpginfo.getPublicKeyRing());
			} catch (final IOException e) {
				LOG.debug("Failed to export keyring to {}", keyfile, e);
				throw new RepositoryException(e);
			}

			RepoUtils.touch(Paths.get(ascPath));
			RepoUtils.touch(Paths.get(keyPath));
		}

		RepoUtils.touch(repomdfile);
		updateLastIndexed();
		updateMetadata();
		return true;
	}

	public void generateDeltas() throws RepositoryException {
		final Path root = getRoot();
		LOG.info("Generating deltas for {}", this);
		RPMUtils.generateDeltas(root.toFile());
		LOG.debug("Finished generating deltas for {}", this);
	}

	public void cleanUpDeltas() throws RepositoryException {
		refresh();
		final Path drpmPath = getRoot().resolve("drpms");
		if (!drpmPath.toFile().exists()) {
			return;
		}
		try {
			Files.walk(drpmPath).forEach(path -> {
				if (path.toFile().isDirectory()) {
					return;
				}
				final String drpmName = path.getFileName().toString();
				final Matcher m = DRPM.matcher(drpmName);
				if (m.matches()) {
					// LOG.debug("matches: {}", path);
					final String name = m.group(1);
					final String fromEpoch = m.group(2);
					final String fromVersion = m.group(3);
					final String fromRevision = m.group(4);
					final String toEpoch = m.group(5);
					final String toVersion = m.group(6);
					final String toRevision = m.group(7);
					// final String arch = m.group(8);

					final RPMVersion from = new RPMVersion(fromEpoch == null ? 0 : Integer.valueOf(fromEpoch), fromVersion, fromRevision);
					final RPMVersion to = new RPMVersion(toEpoch == null ? 0 : Integer.valueOf(toEpoch), toVersion, toRevision);

					final RPMPackage drpm = RPMUtils.getPackage(path);
					final RepositoryPackage latest = getPackage(drpm.getUniqueName());
					LOG.debug("package: {}, from={}, to={}, latest={}", name, from, to, latest == null ? null : latest.getVersion());

					if (latest == null || !latest.getVersion().equals(to)) {
						LOG.debug("Removing stale DRPM: {}", drpmName);
						RepoUtils.delete(path);
					} else {
						LOG.debug("Keeping DRPM: {}", drpmName);
					}
				} else {
					LOG.warn("Unknown file in DRPM directory: {}", path);
				}
			});
		} catch (final Exception e) {
			throw new RepositoryException(e);
		}
	}

	protected boolean isDirty() {
		final Path root = getRoot();
		try {
			final long lastIndexed = getLastIndexed();
			final Optional<FileTime> res = Files.walk(root).filter(path -> {
				return !path.startsWith(root.resolve("repodata")) && !RepoUtils.isMetadata(path);
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

			LOG.trace("newest repodata edit: {} {}", lastIndexed, this);
			if (res.isPresent()) {
				final long reduced = res.get().toMillis();
				LOG.trace("newest other file: {} {}", reduced, this);
				return reduced > lastIndexed;
			} else {
				LOG.warn("No file times found in repository {}!", this);
				return false;
			}
		} catch (final Exception e) {
			LOG.warn("Failed while checking for a dirty repository: {}", this, e);
			return true;
		}
	}

	@Override
	public Repository cloneInto(final Path to) {
		RepoUtils.cloneDirectory(getRoot(), to);
		final SortedSet<Repository> repos = new TreeSet<>();
		repos.add(this);
		return new RPMRepository(to, repos);
	}

	@Override
	protected String getRepositoryTypeName() {
		return "RPM";
	}
}
