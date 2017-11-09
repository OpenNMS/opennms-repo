package org.opennms.repo.impl.actions;

import java.io.PrintStream;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

import org.kohsuke.args4j.Argument;
import org.kohsuke.args4j.CmdLineException;
import org.kohsuke.args4j.CmdLineParser;
import org.kohsuke.args4j.Option;
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

	@Option(name = "--type", aliases = { "-t" }, required = false, usage = "the repository type (rpm, rpm-meta, deb) to index", metaVar = "<type>")
	private String m_metaType;

	@Argument
	public List<String> m_arguments = new ArrayList<>();

	private final Path m_target;
	private final String m_name;

	public BlessAction() {
		m_target = null;
		m_name = null;
	}

	public BlessAction(final Options options, final List<String> arguments) {
		super();

		final CmdLineParser parser = new CmdLineParser(this);
		try {
			parser.parseArgument(arguments);
		} catch (final CmdLineException e) {
			throw new RepositoryException("Unable to parse '" + options.getAction() + "' action arguments: " + e.getMessage(), e);
		}

		if (m_arguments.size() == 0) {
			throw new IllegalArgumentException("You must specify a target repository to bless!");
		}

		final Path target = Paths.get(m_arguments.get(0));
		m_name = m_arguments.size() > 1? m_arguments.get(1) : null; 

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
			LOG.debug("Bless updating repository metadata: " + repo.getRoot());
			repo.getMetadata().store();
		});

		final Path commonPath = m_target.resolve("common").resolve("repodata");

		RepositoryMetadata repo = null;
		if ("rpm-meta".equals(m_metaType)) {
			repo = RepositoryMetadata.getInstance(m_target, RPMMetaRepository.class);
		} else if ("rpm".equals(m_metaType)) {
			repo = RepositoryMetadata.getInstance(m_target, RPMRepository.class);
		} else if (commonPath.toFile().exists() && commonPath.toFile().isDirectory()) {
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
		out.println("Usage: bless [options] <repository> [name]");
		out.println("");

		final CmdLineParser parser = new CmdLineParser(this);
		parser.printUsage(out);
	}

}
