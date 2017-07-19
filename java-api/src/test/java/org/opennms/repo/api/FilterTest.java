package org.opennms.repo.api;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import org.junit.Test;

public class FilterTest {

	@Test
	public void testMatchJicmp() {
		final RepositoryPackage pack = mock(RepositoryPackage.class);
		when(pack.getName()).thenReturn("jicmp");
		assertTrue(new NameRegexFilter("^jicmp$").test(pack));
		assertTrue(new NameRegexFilter("^jicmp").test(pack));
		assertTrue(new NameRegexFilter("jicmp$").test(pack));
		assertTrue(new NameRegexFilter("jicmp").test(pack));
		assertFalse(new NameRegexFilter("jicmp6").test(pack));
		assertFalse(new NameRegexFilter("opennms").test(pack));
	}

	@Test
	public void testMatchJicmp6() {
		final RepositoryPackage pack = mock(RepositoryPackage.class);
		when(pack.getName()).thenReturn("jicmp6");
		assertFalse(new NameRegexFilter("^jicmp$").test(pack));
		assertTrue(new NameRegexFilter("^jicmp").test(pack));
		assertTrue(new NameRegexFilter("^jicmp6$").test(pack));
		assertTrue(new NameRegexFilter("jicmp").test(pack));
		assertFalse(new NameRegexFilter("opennms").test(pack));
	}

}
