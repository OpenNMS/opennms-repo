package org.opennms.repo.impl.deb;

import org.opennms.repo.api.BaseVersion;

public class DebVersion extends BaseVersion {

	public DebVersion(final String version) {
		super(version);
	}

	public DebVersion(final int epoch, final String version) {
		super(epoch, version);
	}

	public DebVersion(final String version, final String release) {
		super(version, release);
	}

	public DebVersion(final int epoch, final String version, final String release) {
		super(epoch, version, release);
	}
}
