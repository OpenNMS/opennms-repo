package org.opennms.repo.impl.actions;

import java.io.File;
import java.io.PrintStream;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

import org.kohsuke.args4j.Argument;
import org.kohsuke.args4j.CmdLineException;
import org.kohsuke.args4j.CmdLineParser;
import org.kohsuke.args4j.Option;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.impl.GPGUtils;
import org.opennms.repo.impl.Options;
import org.opennms.repo.impl.rpm.RPMMetaRepository;
import org.opennms.repo.impl.rpm.RPMRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class IndexAction implements Action {
	private static final Logger LOG = LoggerFactory.getLogger(IndexAction.class);

	@Option(name = "--type", aliases = {
			"-t" }, required = false, usage = "the repository type (rpm, deb) to index", metaVar = "<type>")
	public String m_type;

	@Argument
	public List<String> m_arguments = new ArrayList<>();

	private final Path m_repoPath;
	private final Options m_options;

	public IndexAction() {
		m_repoPath = null;
		m_options = null;
	}

	public IndexAction(final Options options, final List<String> arguments) {
		final CmdLineParser parser = new CmdLineParser(this);
		try {
			parser.parseArgument(arguments);
		} catch (final CmdLineException e) {
			throw new RepositoryException("Unable to parse 'index' action arguments: " + e.getMessage(), e);
		}

		if (m_arguments.size() != 1) {
			throw new IllegalStateException("You must specify a repository to index!");
		}

		m_repoPath = Paths.get(m_arguments.get(0));
		m_options = options;

		if (!m_repoPath.toFile().exists()) {
			throw new IllegalStateException("Repository " + m_repoPath + " does not exist!");
		}

		if (options.isGPGConfigured()) {
			LOG.info("index: indexing {} using GPG key {}", m_repoPath, options.getKeyId());
		} else {
			LOG.warn("index: indexing {} without a GPG key!", m_repoPath);
		}
	}

	@Override
	public void run() throws ActionException {
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
			final RepositoryMetadata metadata = RepositoryMetadata.getInstance(m_repoPath, null, null, null);
			repo = metadata.getRepositoryInstance();
		}

		if (m_options.isGPGConfigured()) {
			final GPGInfo gpginfo = GPGUtils.fromKeyRing(m_options.getKeyRing(), m_options.getKeyId(),
					m_options.getPassword());
			repo.index(gpginfo);
		} else {
			repo.index();
		}
		repo.refresh();
	}

	@Override
	public String getDescription() {
		return "Index the specified repository.";
	}

	@Override
	public void printUsage(final PrintStream out) {
		out.println("Usage: index [options] <repository>");
		out.println("");

		final CmdLineParser parser = new CmdLineParser(this);
		parser.printUsage(out);
	}

}
