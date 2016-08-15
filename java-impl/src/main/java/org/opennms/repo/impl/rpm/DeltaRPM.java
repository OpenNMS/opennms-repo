package org.opennms.repo.impl.rpm;

import java.nio.file.Path;

public class DeltaRPM {
	private RPMPackage m_from;
	private RPMPackage m_to;

	public DeltaRPM(final RPMPackage a, final RPMPackage b) {
		if (!a.getArchitecture().equals(b.getArchitecture())) {
			throw new IllegalArgumentException("RPMs are not the same architecture!");
		}

		if (a.isLowerThan(b)) {
			m_from = a;
			m_to = b;
		} else {
			m_from = b;
			m_to = a;
		}
	}

	public Path getFilePath(final Path outputDirectory) {
		return outputDirectory.resolve(getFileName());
	}

	public String getFileName() {
		final RPMPackage first = m_from;
		final RPMPackage second = m_to;

		final StringBuilder sb = new StringBuilder();
		sb.append(first.getName()).append("-");
		sb.append(first.getVersion().toStringWithoutEpoch()).append("_");
		sb.append(second.getVersion().toStringWithoutEpoch()).append(".");
		sb.append(first.getArchitectureString()).append(".drpm");
		return sb.toString();
	}

	public RPMPackage getFromRPM() {
		return m_from;
	}

	public RPMPackage getToRPM() {
		return m_to;
	}

	@Override
	public String toString() {
		return getFileName();
	}
}
