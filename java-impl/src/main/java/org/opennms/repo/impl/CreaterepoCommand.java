package org.opennms.repo.impl;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.file.Path;

import org.apache.commons.exec.CommandLine;
import org.apache.commons.exec.launcher.CommandLauncherFactory;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class CreaterepoCommand extends Command {
    private static final Logger LOG = LoggerFactory.getLogger(CreaterepoCommand.class);

    private final Path m_root;

    private boolean m_supportsChecksum;
    //private boolean m_supportsDeltas;
    private boolean m_supportsUpdate;

    public CreaterepoCommand(Path root) throws RepositoryException {
        super("createrepo");
        m_root = root;

        try {
            init();
        } catch (final IOException | InterruptedException e) {
            throw new RepositoryException(e);
        }
    }

    public CreaterepoCommand update(final boolean update) {
        if (update) {
            if  (m_supportsUpdate) {
                this.addArgument("--update");
            } else {
                throw new IllegalStateException("System createrepo doesn't support --update!");
            }
        }
        return this;
    }

    private void init() throws IOException, InterruptedException {
        LOG.debug("CreaterepoCommand.init()");

        final CommandLine cl = new CommandLine("createrepo").addArgument("--help");
        LOG.debug("CreaterepoCommand.init(): command line = {}", cl);

        final Process p = CommandLauncherFactory.createVMLauncher().exec(cl, getEnvironment());

        LOG.debug("CreaterepoCommand.init(): process created: {}", p);
        try (final InputStream s = p.getInputStream(); final Reader r = new InputStreamReader(s); final BufferedReader br = new BufferedReader(r);) {
            LOG.debug("s={}, r={}, br={}", s, r, br);
            String line = null;
            do {
                line = br.readLine();
                if (line == null) {
                    break;
                }
                if (line.contains("--checksum=")) {
                    m_supportsChecksum = true;
                    /*
                } else if (line.contains("--deltas")) {
                    m_supportsDeltas = true;
                     */
                } else if (line.contains("--update")) {
                    m_supportsUpdate = true;
                }
            } while (line != null);
        }
        p.waitFor();

        if (m_supportsChecksum) {
            this.addArgument("--checksum");
            this.addArgument("sha");
        }
    }

    public void run() {
        final String rootDirectory = m_root.toAbsolutePath().toString();

        try {
            final CommandLine exec = new CommandLine(this.getExecutable());
            exec.addArguments(this.getArguments());
            exec.addArgument("--outputdir").addArgument(rootDirectory);
            exec.addArgument(rootDirectory);
            exec.setSubstitutionMap(this.getSubstitutionMap());
            final Process p = CommandLauncherFactory.createVMLauncher().exec(exec, getEnvironment());
            p.waitFor();
        } catch (final IOException | InterruptedException e) {
            throw new RepositoryIndexException(e);
        }
    }
}
