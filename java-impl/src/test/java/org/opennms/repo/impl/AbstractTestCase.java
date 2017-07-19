package org.opennms.repo.impl;

import java.nio.file.Path;
import java.nio.file.Paths;

import org.junit.Before;
import org.junit.BeforeClass;
import org.junit.Rule;
import org.junit.rules.TestName;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Util;
import org.slf4j.LoggerFactory;

public class AbstractTestCase {
	@Rule public TestName m_test = new TestName();
	
	private static GPGInfo s_gpginfo;
	protected static final Path s_repositoryTestRoot = Paths.get("target", "repositories");

	@BeforeClass
	public static void generateGPG() throws Exception {
		s_gpginfo = TestUtils.generateGPGInfo();
	}

	@Before
	public void cleanUpPreviousTestOutput() throws Exception {
		final Path repositoryPath = getRepositoryPath();
		LoggerFactory.getLogger(this.getClass()).debug("Cleaning up test repository: {}", repositoryPath);
		Util.recursiveDelete(repositoryPath);
	}

	protected GPGInfo getGPGInfo() {
		return s_gpginfo;
	}

	protected Path getRepositoryPath() {
		return s_repositoryTestRoot.resolve(this.getClass().getSimpleName()).resolve(m_test.getMethodName());
	}
}
