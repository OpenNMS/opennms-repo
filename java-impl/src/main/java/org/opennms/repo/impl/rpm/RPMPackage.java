package org.opennms.repo.impl.rpm;

import java.io.File;
import java.nio.file.Path;
import java.util.Objects;

import org.opennms.repo.api.RepositoryPackage;
import org.opennms.repo.api.Version;

public class RPMPackage implements org.opennms.repo.api.RepositoryPackage {
	private final String m_name;
	private final RPMVersion m_version;
	private final Architecture m_architecture;
	private final Path m_path;

	public RPMPackage(final String name, final RPMVersion version, final Architecture arch, final Path path) {
		if (name == null || version == null || arch == null || path == null) {
			throw new IllegalArgumentException("All arguments to RPMPackage() are required!");
		}
		m_name = name;
		m_version = version;
		m_architecture = arch;
		m_path = path;
	}

	public RPMPackage(final String name, final int epoch, final String version, final String release, final Architecture arch, final Path path) {
		this(name, new RPMVersion(epoch, version, release), arch, path);
	}

	@Override
	public int compareTo(final RepositoryPackage o) {
		int ret = m_name.compareTo(o.getName());
		if (ret == 0) {
			ret = m_version.compareTo(o.getVersion());
		}
		if (ret == 0) {
			ret = m_architecture.compareTo(o.getArchitecture());
		}
		return ret;
	}

	@Override
	public File getFile() {
		return m_path.toFile();
	}

	@Override
	public Path getPath() {
		return m_path;
	}

	@Override
	public String getName() {
		return m_name;
	}

	@Override
	public Version getVersion() {
		return m_version;
	}

	@Override
	public Architecture getArchitecture() {
		return m_architecture;
	}

	@Override
	public int hashCode() {
		final int prime = 139;
		int result = 1;
		result = prime * result + ((m_architecture == null) ? 0 : m_architecture.hashCode());
		result = prime * result + ((m_name == null) ? 0 : m_name.hashCode());
		result = prime * result + ((m_path == null) ? 0 : m_path.hashCode());
		result = prime * result + ((m_version == null) ? 0 : m_version.hashCode());
		return result;
	}

	@Override
	public boolean equals(final Object obj) {
		if (this == obj) {
			return true;
		}
		if (obj == null) {
			return false;
		}
		if (getClass() != obj.getClass()) {
			return false;
		}
		final RPMPackage that = (RPMPackage) obj;
		return Objects.equals(this.m_name, that.m_name) && Objects.equals(m_version, that.m_version) && Objects.equals(m_architecture, that.m_architecture)
				&& Objects.equals(m_path.toAbsolutePath(), that.m_path.toAbsolutePath());
	}

	public String getArchitectureString() {
		switch (m_architecture) {
		case I386:
			return "i386";
		case AMD64:
			return "x86_64";
		default:
			return "noarch";
		}
	}

	public String getNameKey() {
		return m_name + "." + m_architecture;
	}

	@Override
	public String toString() {
		return m_name + "-" + m_version.toString() + "." + getArchitectureString() + ".rpm";
	}

	@Override
	public boolean isLowerThan(final RepositoryPackage pack) {
		return this.compareTo(pack) == -1;
	}

	@Override
	public boolean isHigherThan(final RepositoryPackage pack) {
		return this.compareTo(pack) == 1;
	}
}