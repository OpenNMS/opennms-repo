package org.opennms.repo.impl.actions;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Date;

import org.ocpsoft.prettytime.PrettyTime;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.GPGUtils;
import org.opennms.repo.impl.Options;
import org.opennms.repo.impl.RepoUtils;
import org.opennms.repo.impl.rpm.RPMMetaRepository;
import org.opennms.repo.impl.rpm.RPMRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class AbstractIndexAction implements Action {
	private static final Logger LOG = LoggerFactory.getLogger(AbstractIndexAction.class);

	private String m_type;
	private Path m_repoPath;
	private Options m_options;

	public AbstractIndexAction() {
		m_options = new Options("unknown");
	}

	protected void initialize(final Options options, final String type, final Path repoPath) {
		m_options = options;
		m_type = type;
		m_repoPath = repoPath;

		if (options.isGPGConfigured()) {
			LOG.info("{}: Indexing {} using GPG key {}", options.getAction(), m_repoPath, options.getKeyId());
		} else {
			LOG.warn("{}: Indexing {} without a GPG key!", options.getAction(), m_repoPath);
		}
	}

	protected Options getOptions() {
		return m_options;
	}

	protected Path getRepoPath() {
		return m_repoPath;
	}

	protected String getType() {
		return m_type;
	}

	protected abstract void performRepoOperations(Repository repo);

	@Override
	public void run() {
		final Date start = new Date();

		final Repository repo = getRepository();

		boolean changed = false;
		final Repository cloned;
		try {
			cloned = repo.cloneInto(Files.createTempDirectory(repo.getRoot().getParent(), ".repo-"));
		} catch (final IOException e) {
			LOG.error("{}: Failed to clone {} into temporary repository.", m_options.getAction(), repo, e);
			throw new RepositoryException("Failed to clone " + repo + " into temporary repository.", e);
		}

		cloned.refresh();
		performRepoOperations(cloned);

		if (m_options.isGPGConfigured()) {
			final GPGInfo gpginfo = GPGUtils.fromKeyRing(m_options.getKeyRing(), m_options.getKeyId(), m_options.getPassword());
			changed = cloned.index(gpginfo);
		} else {
			changed = cloned.index();
		}
		RepoUtils.atomicReplace(cloned.getRoot(), repo.getRoot());
		RepositoryMetadata.getInstance(repo.getRoot()).getRepositoryInstance().refresh();

		if (changed) {
			LOG.info("{}: Index of repository {} completed in {}", m_options.getAction(), Util.relativize(m_repoPath), new PrettyTime().format(start).replaceAll(" ago$", ""));
		} else {
			LOG.info("{}: Index of repository {} was not necessary.", m_options.getAction(), Util.relativize(m_repoPath));
		}
	}

	protected Repository getRepository() {
		final Repository repo;
		if (m_type != null) {
			if ("rpm".equalsIgnoreCase(m_type)) {
				final File commonDirectory = m_repoPath.resolve("common").toFile();
				if (commonDirectory.exists() && commonDirectory.isDirectory()) {
					repo = new RPMMetaRepository(m_repoPath);
				} else {
					repo = new RPMRepository(m_repoPath);
				}
			} else if ("deb".equalsIgnoreCase(m_type)) {
				throw new UnsupportedOperationException("Not yet implemented!");
			} else {
				throw new IllegalArgumentException("Unknown repository type: " + m_type);
			}
		} else {
			final RepositoryMetadata metadata = RepositoryMetadata.getInstance(m_repoPath);
			repo = metadata.getRepositoryInstance();
		}
		return repo;
	}

}
