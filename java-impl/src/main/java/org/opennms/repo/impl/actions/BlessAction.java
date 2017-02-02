package org.opennms.repo.impl.actions;

import java.io.PrintStream;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.impl.Options;
import org.opennms.repo.impl.RepoUtils;
import org.opennms.repo.impl.rpm.RPMMetaRepository;
import org.opennms.repo.impl.rpm.RPMRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class BlessAction implements Action {
	private static final Logger LOG = LoggerFactory.getLogger(BlessAction.class);

	private final Path m_target;
	private final String m_name;

	public BlessAction() {
		m_target = null;
		m_name = null;
	}

	public BlessAction(final Options options, final List<String> arguments) {
		if (arguments.size() == 0) {
			throw new IllegalArgumentException("You must specify a target repository to bless!");
		}

		final Path target = Paths.get(arguments.get(0));
		m_name = arguments.size() > 1? arguments.get(1) : null; 

		if (target.toFile().exists() && target.toFile().isDirectory()) {
			m_target = target;
			LOG.info("bless: {}", m_target);
		} else {
			throw new RepositoryException("Target repository " + target + " does not exist or is invalid!");
		}
	}

	@Override
	public void run() {
		RepoUtils.findRepositories(m_target).forEach(repo -> {
			System.err.println("Found repository: " + repo.getRoot());
			repo.getMetadata().store();
		});

		final Path commonPath = m_target.resolve("common").resolve("repodata");
		
		RepositoryMetadata repo = null;
		if (commonPath.toFile().exists() && commonPath.toFile().isDirectory()) {
			repo = RepositoryMetadata.getInstance(m_target, RPMMetaRepository.class);
		} else {
			repo = RepositoryMetadata.getInstance(m_target, RPMRepository.class);
		}
		if (m_name != null) {
			repo.setName(m_name);
		}
		repo.store();
	}

	@Override
	public String getDescription() {
		return "Bless a repository.";
	}

	@Override
	public void printUsage(final PrintStream out) {
		out.println("Usage: bless <repository> [name]");
		out.println("");
	}

}
