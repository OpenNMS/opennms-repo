package org.opennms.repo.impl;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import org.apache.commons.exec.CommandLine;
import org.apache.commons.exec.launcher.CommandLauncherFactory;
import org.apache.commons.io.IOUtils;
import org.opennms.repo.api.RepositoryIndexException;

public class RsyncCommand extends Command {
	private final Path m_from;
	private final Path m_to;
	private List<String> m_output;
	private List<String> m_errorOutput;

	public RsyncCommand(final Path from, final Path to) {
		super("rsync");
		m_from = from;
		m_to = to;
	}

	@Override
	public void run() {
		try {
			Files.createDirectories(m_to);
			final CommandLine exec = new CommandLine(this.getExecutable());
			exec.addArgument("-a");
			exec.addArgument("-r");
			exec.addArgument("--delete");
			exec.addArgument("--link-dest").addArgument(m_from.toAbsolutePath() + File.separator);
			exec.addArgument(m_from.toAbsolutePath() + File.separator);
			exec.addArgument(m_to.toAbsolutePath() + File.separator);
			LOG.debug("rsync: running 'rsync {}'", String.join(" ", exec.getArguments()));
			final Process p = CommandLauncherFactory.createVMLauncher().exec(exec, getEnvironment());
			p.waitFor();

			try (final InputStream err = p.getErrorStream(); final InputStream out = p.getInputStream()) {
				m_output = IOUtils.readLines(out, Charset.defaultCharset());
				m_errorOutput = IOUtils.readLines(err, Charset.defaultCharset());
			}
			m_output.forEach(line -> {
				LOG.debug("rsync: DEBUG: {}", line);
			});
			m_errorOutput.forEach(line -> {
				LOG.warn("rsync: WARN: {}", line);
			});
		} catch (final IOException | InterruptedException e) {
			throw new RepositoryIndexException(e);
		}

	}

	@Override
	public List<String> getOutput() {
		return m_output;
	}

	@Override
	public List<String> getErrorOutput() {
		return m_errorOutput;
	}

}
