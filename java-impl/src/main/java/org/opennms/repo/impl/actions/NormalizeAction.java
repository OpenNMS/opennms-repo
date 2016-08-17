package org.opennms.repo.impl.actions;

import java.io.PrintStream;
import java.util.List;

import org.kohsuke.args4j.CmdLineParser;
import org.opennms.repo.api.Repository;
import org.opennms.repo.impl.Options;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class NormalizeAction extends AbstractIndexAction {
	private static final Logger LOG = LoggerFactory.getLogger(NormalizeAction.class);

	public NormalizeAction() {
		super();
	}

	public NormalizeAction(final Options options, final List<String> arguments) {
		super(options, arguments);
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
