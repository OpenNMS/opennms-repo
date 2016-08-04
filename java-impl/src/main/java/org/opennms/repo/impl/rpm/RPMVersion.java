package org.opennms.repo.impl.rpm;

import org.opennms.repo.api.BaseVersion;

public class RPMVersion extends BaseVersion {

	public RPMVersion(final String version) {
		super(version);
	}

	public RPMVersion(final int epoch, final String version) {
		super(epoch, version);
	}

	public RPMVersion(final String version, final String release) {
		super(0, version, release);
	}

	public RPMVersion(final int epoch, final String version, final String release) {
		super(epoch, version, release);
	}
}
