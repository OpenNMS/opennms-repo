package org.opennms.repo.impl.actions;

import java.io.PrintStream;
import java.util.List;

import org.kohsuke.args4j.CmdLineParser;
import org.opennms.repo.api.Repository;
import org.opennms.repo.impl.Options;

public class IndexAction extends AbstractIndexAction {
	public IndexAction() {
		super();
	}

	public IndexAction(final Options options, final List<String> arguments) {
		super(options, arguments);
	}

	@Override public void performRepoOperations(final Repository repo) {
		// do nothing, the AbstractIndexAction will take care of actual indexing
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
