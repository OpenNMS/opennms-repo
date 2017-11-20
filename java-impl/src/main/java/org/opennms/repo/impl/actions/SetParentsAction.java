package org.opennms.repo.impl.actions;

import java.io.PrintStream;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.stream.Collectors;

import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.Options;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class SetParentsAction implements Action {
	private static final Logger LOG = LoggerFactory.getLogger(SetParentsAction.class);

	private final RepositoryMetadata m_target;
	private final Collection<RepositoryMetadata> m_parents;

	public SetParentsAction() {
		m_target  = null;
		m_parents = null;
	}

	public SetParentsAction(final Options options, final List<String> arguments) {
		if (arguments.size() < 2) {
			throw new IllegalArgumentException("You must specify a target and at least one parent repository!");
		}

		final Path target = Paths.get(arguments.get(0));
		m_parents = arguments.subList(1, arguments.size()).parallelStream().map(pathString -> {
			final Path path = Paths.get(pathString).normalize().toAbsolutePath();
			if (!path.toFile().exists() || !path.toFile().isDirectory()) {
				throw new RepositoryException("Parent repository path " + Util.relativize(path) + " does not exist or is invalid!");
			}
	
			try {
				final RepositoryMetadata parentMetadata = RepositoryMetadata.getInstance(path);
				parentMetadata.getRepositoryInstance();
				return parentMetadata;
			} catch (final Exception e) {
				throw new RepositoryException("parent repository path " + Util.relativize(path) + " exists, but is invalid!", e);
			}
		}).sorted().distinct().collect(Collectors.toList());

		if (!target.toFile().exists() || !target.toFile().isDirectory()) {
			throw new RepositoryException("Target repository path " + Util.relativize(target) + " does not exist or is invalid!");
		}

		try {
			m_target = RepositoryMetadata.getInstance(target, null, null, null);
		} catch (final Exception e) {
			throw new RepositoryException("Target repository " + target + " exists, but is invalid!", e);
		}

		if (!m_target.getRepositoryInstance().isValid()) {
			throw new RepositoryException("Target repository " + m_target.getName() + " exists, but is invalid!");
		}

		LOG.info("set-parents: {} on repository {}", String.join("/", m_parents.stream().map(parent -> {
			return parent.getName();
		}).toArray(String[]::new)), m_target);
	}

	@Override
	public void run() {
		final List<Path> parentPaths = new ArrayList<>();
		Class<? extends Repository> type = null;
		
		for (final RepositoryMetadata parent : m_parents) {
			parentPaths.add(parent.getRoot());
			final String parentTypeName = parent.getType().getName();
			if (type == null) {
				if (!parentTypeName.equals(m_target.getType().getName())) {
					throw new RepositoryException("Parent repository '" + parent.getName() + "' type does not match target repository '" + m_target.getName() + "' (" + parent.getType() + " != " + m_target.getType() + ")");
				}
				type = parent.getType();
			} else if (!type.getName().equals(parentTypeName)) {
				throw new RepositoryException("Multiple parent repositories specified, but their types don't match!");
			}
		};

		final RepositoryMetadata target = RepositoryMetadata.getInstance(m_target.getRoot(), m_target.getType(), parentPaths, type);
		target.store();
	}

	@Override
	public String getDescription() {
		return "Manually set one or more parent repositories on a repository.";
	}

	@Override
	public void printUsage(final PrintStream out) {
		out.println("Usage: set-parents <target> <parent> [additional parents...]");
		out.println("");
	}

}
