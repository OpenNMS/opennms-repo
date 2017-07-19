package org.opennms.repo.api;

import java.io.File;
import java.nio.file.Path;

public interface RepositoryPackage extends Comparable<RepositoryPackage> {
	public enum Architecture {
		I386, AMD64, ALL, SOURCE
	}

	/** the location of the file on disk */
	public File getFile();

	/** the path of the file on disk */
	public Path getPath();

	/** the name of the package */
	public String getName();

	/** an architecture-specific unique name of the package */
	public String getUniqueName();

	/** a sortable name */
	public String getCollationName();

	/** the package's version (including epoch and revision) */
	public Version getVersion();

	/** the CPU architecture of the package */
	public Architecture getArchitecture();

	/** whether this package is sorted lower than the given package */
	public boolean isLowerThan(final RepositoryPackage pack);

	/** whether this package is sorted higher than the given package */
	public boolean isHigherThan(final RepositoryPackage pack);
}
