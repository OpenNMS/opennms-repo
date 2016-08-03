package org.opennms.repo.impl;

import java.io.File;
import java.lang.reflect.Constructor;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

import org.kohsuke.args4j.Argument;
import org.kohsuke.args4j.CmdLineParser;
import org.kohsuke.args4j.Option;
import org.opennms.repo.impl.actions.Action;
import org.opennms.repo.impl.actions.CloneAction;
import org.opennms.repo.impl.actions.IndexAction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.LoggerContext;

public class Main {
	private static final Logger LOG = LoggerFactory.getLogger(Main.class);

	@Option(name="--keyring", aliases = {"-r"}, required=false, usage="PGP/GPG keyring file to use for signing", metaVar="</path/to/secring.gpg>")
    public String m_keyRing = System.getProperty("user.home") + File.separator + ".gnupg" + File.separator + "secring.gpg";

	@Option(name="--key", aliases = {"-k"}, required=false, usage="PGP/GPG key ID to use for signing", metaVar="<gpg-key>")
    public String m_keyId = "opennms@opennms.org";

    @Option(name="--password", aliases = {"-p"}, required=false, usage="PGP/GPG password to use for signing", metaVar="<gpg-password>")
    public String m_password;

    @Option(name="--debug", aliases = {"-d"}, required=false, usage="enable debug logging")
    public boolean m_debug = false;

    @Argument
    public List<String> m_arguments = new ArrayList<>();

    private CmdLineParser m_parser;

    public static void main(final String... args) {
        new Main().doMain(args);
    }

    public void doMain(final String... args) {
        m_parser = new CmdLineParser(this);
        try {
            m_parser.parseArgument(args);
        } catch (final Exception e) {
            printUsage(e.getMessage());
        }

        if (m_debug) {
        	LoggerContext lc = (LoggerContext) LoggerFactory.getILoggerFactory();
        	lc.getLogger("root").setLevel(Level.DEBUG);
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
        LOG.debug("Action = {}", action);

        switch (action.toLowerCase()) {
        	case "clone": runCommand(CloneAction.class); break;
        	case "index": runCommand(IndexAction.class); break;
        	default: printUsage("Unknown action: " + action); break;
        }
        System.exit(0);
    }

    private void runCommand(final Class<? extends Action> action) {
    	LOG.debug("Running {}({})", action, m_arguments);
    	try {
    		final Constructor<? extends Action> constructor = action.getConstructor(Options.class, List.class);
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
    		final Action runme = constructor.newInstance(m_arguments);
			runme.run();
		} catch (final Throwable t) {
			LOG.debug("Error running {}({})", action, m_arguments, t);
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
    	System.err.println("Usage: opennms-repo [-k <gpg-key>] [-p <gpg-password>] [-s <sub-repository>] <action> [arguments]");
    	if (errorMessage != null) {
    		System.err.println("ERROR: " + errorMessage);
    	}
    	System.err.println("");

        m_parser.printUsage(System.err);
    	System.err.println("");

    	System.err.println("Actions:\n");

    	System.err.println("");
    	System.exit(1);
    }
}
