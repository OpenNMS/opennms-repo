package org.opennms.repo.api;

import java.util.regex.Pattern;

public class NameRegexFilter implements Filter {
	private final Pattern m_pattern;

	public NameRegexFilter(final String pattern) {
		m_pattern = Pattern.compile(pattern);
	}

	@Override
	public boolean test(final RepositoryPackage pack) {
		return m_pattern.matcher(pack.getName()).find();
	}

}
