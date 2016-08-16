package org.opennms.repo.api;

import java.io.File;
import java.nio.file.Path;

public interface RepositoryPackage extends Comparable<RepositoryPackage> {
	public enum Architecture {
		I386, AMD64, ALL
	}

	public File getFile();

	public Path getPath();

	public String getName();

	public String getCollationName();

	public Version getVersion();

	public Architecture getArchitecture();

	public boolean isLowerThan(final RepositoryPackage pack);

	public boolean isHigherThan(final RepositoryPackage pack);
}
