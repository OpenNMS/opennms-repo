package org.opennms.repo.impl;

import java.io.File;
import java.lang.reflect.Constructor;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;

import org.kohsuke.args4j.Argument;
import org.kohsuke.args4j.CmdLineParser;
import org.kohsuke.args4j.Option;
import org.opennms.repo.impl.actions.Action;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.LoggerContext;
import javassist.Modifier;

public class Main {
	private static final Logger LOG = LoggerFactory.getLogger(Main.class);

	@Option(name = "--keyring", aliases = { "-r" }, required = false, usage = "PGP/GPG keyring file to use for signing", metaVar = "</path/to/secring.gpg>")
	public String m_keyRing = System.getProperty("user.home") + File.separator + ".gnupg" + File.separator + "secring.gpg";

	@Option(name = "--key", aliases = { "-k" }, required = false, usage = "PGP/GPG key ID to use for signing", metaVar = "<gpg-key>")
	public String m_keyId = "opennms@opennms.org";

	@Option(name = "--password", aliases = { "-p" }, required = false, usage = "PGP/GPG password to use for signing", metaVar = "<gpg-password>")
	public String m_password;

	@Option(name = "--debug", aliases = { "-d" }, required = false, usage = "enable debug logging")
	public boolean m_debug = false;

	@Option(name = "--trace", aliases = { "-t" }, required = false, usage = "enable trace logging")
	public boolean m_trace = false;

	@Option(name = "--help", aliases = { "-h" }, required = false, usage = "this help", help = true, hidden = true)
	public boolean m_help = false;

	@Argument
	public List<String> m_arguments = new ArrayList<>();

	private CmdLineParser m_parser;

	public static void main(final String... args) {
		new Main().doMain(args);
	}

	public void doMain(final String... args) {
		final Set<String> commands = getActions();
		m_parser = new CmdLineParser(this);
		try {
			boolean done = false;
			final List<String> before = new ArrayList<>();
			final List<String> after = new ArrayList<>();
			for (final String arg : args) {
				if (done) {
					after.add(arg);
				} else if ("--".equals(arg)) {
					done = true;
				} else if (commands.contains(arg.toLowerCase())) {
					done = true;
					after.add(arg);
				} else {
					before.add(arg);
				}
			}
			LOG.debug("before: {}", before);
			LOG.debug("after: {}", after);
			m_parser.parseArgument(before);
			m_arguments = new ArrayList<>(m_arguments);
			m_arguments.addAll(after);
			LOG.debug("arguments: {}", m_arguments);
		} catch (final Exception e) {
			printUsage(e.getMessage());
		}

		if (m_help) {
			printUsage(null);
		}

		if (m_debug) {
			LoggerContext lc = (LoggerContext) LoggerFactory.getILoggerFactory();
			lc.getLogger("root").setLevel(Level.DEBUG);
		}
		if (m_trace) {
			LoggerContext lc = (LoggerContext) LoggerFactory.getILoggerFactory();
			lc.getLogger("root").setLevel(Level.TRACE);
		}

		if (m_keyRing != null) {
			final Path keyRing = Paths.get(m_keyRing);
			if (!keyRing.toFile().exists()) {
				LOG.warn("Keyring file {} does not exist!", keyRing);
			}
		}

		if (m_arguments.size() == 0) {
			printUsage("You must specify an action!");
		}

		final String action = m_arguments.remove(0);
		// LOG.debug("Action = {}", action);

		final Class<? extends Action> actionClass = Action.getAction(action);
		LOG.debug("action class: {}", actionClass);
		try {
			runCommand(actionClass);
		} catch (final Throwable t) {
			LOG.debug("Failed to find action {}", action, t);
			printUsage("Unknown action: " + action);
		}

		System.exit(0);
	}

	private Set<String> getActions() {
		final Set<String> actions = new TreeSet<>();
		for (final Class<? extends Action> action : Action.getActions()) {
			actions.add(Action.getActionName(action));
		}
		return actions;
	}

	private void runCommand(final Class<? extends Action> action) {
		final Options options = new Options();
		if (m_keyRing != null) {
			options.setKeyRing(Paths.get(m_keyRing));
		}
		if (m_keyId != null) {
			options.setKeyId(m_keyId);
		}
		if (m_password != null) {
			options.setPassword(m_password);
		}
		options.setAction(Action.getActionName(action));

		LOG.debug("Running {}({}, {})", action, options, m_arguments);
		try {
			final Constructor<? extends Action> constructor = action.getConstructor(Options.class, List.class);
			final Action runme = constructor.newInstance(options, m_arguments);
			runme.run();
		} catch (final Throwable t) {
			LOG.debug("Error running {}({}, {})", action, options, m_arguments, t);
			handleError(t);
		}
	}

	private void handleError(final Throwable t) {
		Throwable cause = t;
		while (cause.getCause() != null) {
			cause = cause.getCause();
		}
		printUsage(cause.getMessage());
	}

	private void printUsage(final String errorMessage) {
		System.err.println("Usage: opennms-repo [-k <gpg-key>] [-p <gpg-password>] [-r </path/to/secring.gpg>] <action> [arguments]");
		if (errorMessage != null) {
			System.err.println("ERROR: " + errorMessage);
		}
		System.err.println("");

		m_parser.printUsage(System.err);
		System.err.println("");

		System.err.println("Actions:\n");
		final Collection<Class<? extends Action>> actions = Action.getActions();
		for (final Class<? extends Action> action : actions) {
			if (Modifier.isAbstract(action.getModifiers())) {
				continue;
			}
			try {
				final String name = Action.getActionName(action);
				final String description = action.newInstance().getDescription();

				System.err.println(name + ": " + description);
			} catch (final Exception e) {
				LOG.warn("Failed to enumerate action {}", action, e);
			}
		}

		System.err.println("");
		System.exit(1);
	}
}
