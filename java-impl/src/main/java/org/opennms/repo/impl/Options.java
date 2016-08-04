package org.opennms.repo.impl;

import java.nio.file.Path;

public class Options {
	private String m_keyId;
	private String m_password;
	private Path m_keyRing;

	public String getKeyId() {
		return m_keyId;
	}

	public void setKeyId(final String keyId) {
		m_keyId = keyId;
	}

	public String getPassword() {
		return m_password;
	}

	public void setPassword(final String password) {
		m_password = password;
	}

	public Path getKeyRing() {
		return m_keyRing;
	}

	public void setKeyRing(final Path keyRing) {
		m_keyRing = keyRing;
	}

	public boolean isGPGConfigured() {
		return m_keyId != null && m_password != null && m_keyRing != null && m_keyRing.toFile().exists();
	}

	@Override
	public String toString() {
		return "Options [keyId=" + m_keyId + ", password=" + (m_password == null ? "not-set" : "set") + ", keyRing="
				+ m_keyRing + "]";
	}

}
