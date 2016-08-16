package org.opennms.repo.impl;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Collection;

import org.junit.Before;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.rpm.RPMRepository;

public class RepoUtilsTest {
	@Before
	// @After
	public void cleanUp() throws IOException {
		Util.recursiveDelete(Paths.get("target/repositories"));
	}

	@Test
	public void testScan() throws Exception {
		final String repositoryPath = "target/repositories/RepoUtilsTest.testScan";
		final GPGInfo gpginfo = TestUtils.generateGPGInfo();

		final Path repoPathA = Paths.get(repositoryPath + File.separator + "a");
		Files.createDirectories(repoPathA);
		final Repository repoA = new RPMRepository(repoPathA);
		assertFalse(repoA.isValid());
		repoA.index(gpginfo);

		final Path repoPathB = Paths.get(repositoryPath + File.separator + "b");
		Files.createDirectories(repoPathB);
		final Repository repoB = new RPMRepository(repoPathB);
		assertFalse(repoB.isValid());
		repoB.index(gpginfo);

		final Collection<Repository> repositories = RepoUtils.findRepositories(Paths.get(repositoryPath));
		assertEquals(2, repositories.size());
	}

	@Test
	public void testCreateTempRepository() throws Exception {
		final String repositoryPath = "target/repositories/RepoUtilsTest.testCreateTempRepository";

		final Path sourceRepoPath = Paths.get(repositoryPath).resolve("source");
		final Repository sourceRepo = new RPMRepository(sourceRepoPath);
		sourceRepo.index();

		final Repository tempRepo = RepoUtils.createTempRepository(sourceRepo);
		assertNotNull(tempRepo);
		assertTrue(tempRepo.isValid());
		assertFalse(tempRepo.hasParent());
	}

	@Test
	public void testCreateTempRepositoryWithParent() throws Exception {
		final String repositoryPath = "target/repositories/RepoUtilsTest.testCreateTempRepositoryWithParent";

		final Path parentRepoPath = Paths.get(repositoryPath).resolve("parent");
		final Repository parentRepo = new RPMRepository(parentRepoPath);
		parentRepo.index();

		final Path sourceRepoPath = Paths.get(repositoryPath).resolve("source");
		final Repository sourceRepo = new RPMRepository(sourceRepoPath, Util.newSortedSet(parentRepo));
		sourceRepo.index();

		final Repository tempRepo = RepoUtils.createTempRepository(sourceRepo);
		assertNotNull(tempRepo);
		assertTrue(tempRepo.isValid());
		assertTrue(tempRepo.hasParent());
		assertEquals(tempRepo.getParents().iterator().next().getRoot().normalize().toAbsolutePath(), parentRepoPath.normalize().toAbsolutePath());
	}
}
