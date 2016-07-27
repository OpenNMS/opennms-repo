package org.opennms.repo.impl.rpm;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collections;
import java.util.List;

import org.apache.commons.exec.CommandLine;
import org.apache.commons.exec.launcher.CommandLauncherFactory;
import org.apache.commons.io.IOUtils;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryIndexException;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.Command;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MakeDeltaRPMCommand extends Command {
    private static final Logger LOG = LoggerFactory.getLogger(MakeDeltaRPMCommand.class);

    private RPMPackage m_fromRPM;
    private RPMPackage m_toRPM;
    private Path m_outputRPM;

    private List<String> m_output;
    private List<String> m_errorOutput;

    public MakeDeltaRPMCommand(final Path fromRPM, final Path toRPM) throws RepositoryException {
        this(fromRPM, toRPM, null);
    }

    public MakeDeltaRPMCommand(final RPMPackage fromRPM, final RPMPackage toRPM) throws RepositoryException {
        this(fromRPM, toRPM, null);
    }

    public MakeDeltaRPMCommand(final Path fromRPM, final Path toRPM, final Path outputRPM) throws RepositoryException {
        this(RPMUtils.getPackage(fromRPM.toFile()), RPMUtils.getPackage(toRPM.toFile()), outputRPM);
    }

    public MakeDeltaRPMCommand(final RPMPackage fromRPM, final RPMPackage toRPM, final Path outputRPM) throws RepositoryException {
        super("makedeltarpm");
        m_fromRPM = fromRPM;
        m_toRPM = toRPM;
        if (!m_fromRPM.getName().equals(m_toRPM.getName())) {
            throw new IllegalArgumentException("RPM packages do not match!  We can't make a delta RPM from unrelated packages.");
        }
        m_outputRPM = outputRPM.toAbsolutePath();
    }

    public MakeDeltaRPMCommand output(final Path outputRPM) {
        m_outputRPM = outputRPM.toAbsolutePath();
        return this;
    }

    public void run() {
        try {
            m_output = Collections.emptyList();
            m_errorOutput = Collections.emptyList();
            final Path outputRPM = getOutputRPMPath();
            Files.createDirectories(outputRPM.getParent());

            final CommandLine exec = new CommandLine(this.getExecutable());
            exec.addArgument(m_fromRPM.getPath().toString());
            exec.addArgument(m_toRPM.getPath().toString());
            exec.addArgument(outputRPM.toString());

            LOG.debug("makedeltarpm {} {} {}", Util.relativize(m_fromRPM.getPath()), Util.relativize(m_toRPM.getPath()), outputRPM);

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

    Path getOutputRPMPath() {
        if (m_outputRPM == null) {
            final String deltaRPMName = RPMUtils.getDeltaFileName(m_fromRPM, m_toRPM);
            return m_fromRPM.getPath().getParent().resolve("drpms").resolve(deltaRPMName);
        }
        return m_outputRPM;
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
