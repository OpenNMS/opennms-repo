package org.opennms.repo.impl.actions;

import java.io.PrintStream;
import java.util.List;

import org.opennms.repo.impl.Options;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class HelpAction implements Action {
	private static final Logger LOG = LoggerFactory.getLogger(HelpAction.class);

	private final String m_action;

	public HelpAction() {
		m_action = null;
	}

	public HelpAction(final Options options, final List<String> arguments) {
		if (arguments.size() < 1) {
			throw new IllegalArgumentException("You must specify an action!");
		}

		m_action = arguments.get(0);
	}

	@Override
	public void run() throws ActionException {
		final Class<? extends Action> actionClass = Action.getAction(m_action);
		LOG.debug("help: {}", actionClass);
		try {
			final Action a = actionClass.newInstance();
			a.printUsage(System.err);
		} catch (final Exception e) {
			LOG.warn("Failed to access help for action {}", m_action, e);
			throw new ActionException(e);
		}
	}

	@Override
	public String getDescription() {
		return "Use 'help <action>' for help with actions.";
	}

	@Override
	public void printUsage(final PrintStream out) {
		out.println("Usage: help <action>");
	}

}
