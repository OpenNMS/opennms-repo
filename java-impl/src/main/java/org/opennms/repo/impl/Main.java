package org.opennms.repo.impl;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

import org.kohsuke.args4j.Argument;
import org.kohsuke.args4j.CmdLineParser;
import org.kohsuke.args4j.Option;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class Main {
	private static final Logger LOG = LoggerFactory.getLogger(Main.class);

	@Option(name="--key", aliases = {"-k"}, required=false, usage="PGP/GPG key ID to use for signing", metaVar="<gpg-key>")
    public String m_keyId = "opennms@opennms.org";

    @Option(name="--password", aliases = {"-p"}, required=false, usage="PGP/GPG password to use for signing", metaVar="<gpg-password>")
    public String m_password;

    @Option(name="--subrepo", aliases = {"-s"}, required=false, usage="specify the sub-repository to use", metaVar="<sub-repo>")
    public String m_subrepo;

    /*
    @Option(name="--clone", aliases = {"-c"}, required=false, usage="clone the specified parent repository before indexing", metaVar="<parent-repo>")
    public String m_cloneRepository;
    */

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

        if (m_arguments.size() == 0) {
            printUsage("You must specify an action!");
        }

        final String action = m_arguments.remove(0);
        LOG.debug("Action = {}", action);

        switch (action.toLowerCase()) {
        	case "clone": cmdCloneRepository(); break;
        	default: printUsage("Unknown action: " + action); break;
        }
        System.exit(0);
    }

    private void cmdCloneRepository() {
    	if (m_arguments.size() != 2) {
    		printUsage("You must specify a source and target repository!");
    	}
    	final Path source = Paths.get(m_arguments.remove(0)).normalize().toAbsolutePath();
    	final Path target = Paths.get(m_arguments.remove(0)).normalize().toAbsolutePath();

    	LOG.info("Cloning {} into {}", source, target);
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
