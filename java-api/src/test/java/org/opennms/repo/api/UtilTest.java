package org.opennms.repo.api;

import static org.junit.Assert.*;

import org.junit.Test;

public class UtilTest {
	@Test
	public void testCollationName() throws Exception {
		assertEquals("jdk", Util.getCollationName("jdk1.8.0_60"));
		assertEquals("opennms", Util.getCollationName("opennms-core"));
		assertEquals("jicmp6", Util.getCollationName("jicmp6"));
	}
}
