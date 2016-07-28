package org.opennms.repo.impl.rpm;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import org.apache.commons.exec.CommandLine;
import org.apache.commons.exec.launcher.CommandLauncherFactory;
import org.apache.commons.io.IOUtils;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.impl.Command;

public class RPMCommand extends Command {
    //private static final Logger LOG = LoggerFactory.getLogger(RPMCommand.class);
    private static final String[] EMPTY_STRING = new String[0];

    private String m_command;
    private Set<String> m_options = new LinkedHashSet<>();
    private final Set<Path> m_rpmFiles = new LinkedHashSet<>();

    private List<String> m_output;
    private List<String> m_errorOutput;

    public RPMCommand() {
        super("rpm");
    }

    public RPMCommand(final Path... rpms) throws RepositoryException {
        super("rpm");
        m_rpmFiles.addAll(Arrays.asList(rpms));
    }

    public RPMCommand query() {
        m_command = "--query";
        return this;
    }

    public RPMCommand query(final String queryFormat) {
        if (queryFormat == null) {
            throw new IllegalArgumentException("Query format must not be null!");
        }
        m_options.add("--queryformat=" + queryFormat);
        return this.query();
    }

    public RPMCommand queryAll() {
        m_options.add("--all");
        return this.query();
    }

    public void run() {
        try {
            m_output = Collections.emptyList();
            m_errorOutput = Collections.emptyList();

            final CommandLine exec = new CommandLine(this.getExecutable());
            exec.addArgument(m_command);
            exec.addArguments(m_options.toArray(EMPTY_STRING));
            if (m_rpmFiles.size() > 0) {
                exec.addArgument("-p");
                m_rpmFiles.stream().forEach(rpm -> exec.addArgument(rpm.toAbsolutePath().toString()));
            }
            exec.setSubstitutionMap(this.getSubstitutionMap());
            final Process p = CommandLauncherFactory.createVMLauncher().exec(exec, getEnvironment());
            p.waitFor();

            try (final InputStream err = p.getErrorStream(); final InputStream out = p.getInputStream()) {
                m_output = IOUtils.readLines(out, Charset.defaultCharset());
                m_errorOutput = IOUtils.readLines(err, Charset.defaultCharset());
            }

        } catch (final IOException | InterruptedException e) {
            throw new RepositoryIndexException(e);
        }
    }

    public List<String> getOutput() {
        if (m_output == null) {
            throw new IllegalStateException("You can't read the output if you have not executed the command yet!");
        }
        return m_output;
    }
    public List<String> getErrorOutput() {
        if (m_errorOutput == null) {
            throw new IllegalStateException("You can't read the error output if you have not executed the command yet!");
        }
        return m_errorOutput;
    }
}
