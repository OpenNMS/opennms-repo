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
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.impl.Options;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class NormalizeAction extends AbstractIndexAction {
	private static final Logger LOG = LoggerFactory.getLogger(NormalizeAction.class);

	@Option(name = "--type", aliases = { "-t" }, required = false, usage = "the repository type (rpm, deb) to index", metaVar = "<type>")
	private String m_type;

	@Argument
	public List<String> m_arguments = new ArrayList<>();

	public NormalizeAction() {
		super();
	}

	public NormalizeAction(final Options options, final List<String> arguments) {
		super();

		final CmdLineParser parser = new CmdLineParser(this);
		try {
			parser.parseArgument(arguments);
		} catch (final CmdLineException e) {
			throw new RepositoryException("Unable to parse '" + options.getAction() + "' action arguments: " + e.getMessage(), e);
		}

		if (m_arguments.size() != 1) {
			throw new IllegalStateException("You must specify a repository to " + options.getAction() + "!");
		}

		final Path repoPath = Paths.get(m_arguments.get(0));

		if (!repoPath.toFile().exists()) {
			throw new IllegalStateException("Repository " + repoPath + " does not exist!");
		}

		initialize(options, m_type, repoPath);
	}

	@Override
	protected void performRepoOperations(final Repository tempRepo) {
		LOG.debug("{}: Normalizing {}", getOptions().getAction(), tempRepo);
		tempRepo.normalize();
	}

	@Override
	public String getDescription() {
		return "Normalize the specified repository layout and then index.";
	}

	@Override
	public void printUsage(final PrintStream out) {
		out.println("Usage: normalize [options] <repository>");
		out.println("");

		final CmdLineParser parser = new CmdLineParser(this);
		parser.printUsage(out);
	}

}
