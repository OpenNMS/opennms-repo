package org.opennms.repo.impl;

import java.io.IOException;
import java.util.Collections;

import org.apache.commons.exec.CommandLine;
import org.apache.commons.exec.launcher.CommandLauncherFactory;

public class CommandBuilder {
    private final CommandLine m_executable;

    protected CommandBuilder(final String executable) {
        m_executable = new CommandLine(executable);
    }
    
    public CommandBuilder builder(final String executable) {
        return new CommandBuilder(executable);
    }

    public void run() throws IOException {
        CommandLauncherFactory.createVMLauncher().exec(m_executable, Collections.emptyMap());
    }
}
