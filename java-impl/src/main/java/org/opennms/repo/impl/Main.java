package org.opennms.repo.impl;

import java.util.List;

import org.kohsuke.args4j.Argument;
import org.kohsuke.args4j.CmdLineParser;
import org.kohsuke.args4j.Option;

public class Main {
    @Option(name="--key", aliases = {"-k"}, required=false, usage="PGP/GPG key ID to use for signing")
    public String m_keyId = "opennms@opennms.org";

    @Option(name="--password", aliases = {"-p"}, required=false, usage="PGP/GPG password to use for signing")
    public String m_password;

    @Option(name="--clone", aliases = {"-c"}, required=false, usage="clone the specified repository before indexing")
    public String m_cloneRepository;

    @Argument
    public List<String> m_arguments;

    public static void main(final String... args) {
        new Main().doMain(args);
    }

    public void doMain(final String... args) {
        final CmdLineParser commandLine = new CmdLineParser(this);
        try {
            commandLine.parseArgument(args);
        } catch (final Exception e) {
            printUsage(commandLine);
        }

        if (m_arguments.size() == 0) {
            printUsage(commandLine);
        }
        System.exit(0);
    }

    private void printUsage(final CmdLineParser commandLine) {
        commandLine.printUsage(System.err);
        System.exit(1);
    }
}
