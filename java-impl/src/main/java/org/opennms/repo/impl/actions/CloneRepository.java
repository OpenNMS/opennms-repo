package org.opennms.repo.impl.actions;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.impl.RepoUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class CloneRepository implements Action {
	private static final Logger LOG = LoggerFactory.getLogger(CloneRepository.class);

	private final RepositoryMetadata m_source;
	private final Path m_target;

	public CloneRepository(final List<String> arguments) {
		if (arguments.size() != 2) {
			throw new IllegalArgumentException("You must specify source and target repositories!");
		}

		final Path source = Paths.get(arguments.get(0));
		m_target = Paths.get(arguments.get(1));
		
		m_source = RepositoryMetadata.getInstance(source);

		LOG.info("clone: {} -> {}", m_source, m_target);
	}

	@Override
	public void run() {
		final Repository tempRepo = RepoUtils.createTempRepository(m_source.getRepositoryInstance());
		RepoUtils.atomicReplace(tempRepo.getRoot(), m_target);
	}

}
