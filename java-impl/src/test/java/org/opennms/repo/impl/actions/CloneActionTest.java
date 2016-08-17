package org.opennms.repo.impl.actions;

import static org.junit.Assert.*;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;

import org.apache.commons.io.FileUtils;
import org.junit.Before;
import org.junit.BeforeClass;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.Options;
import org.opennms.repo.impl.TestUtils;
import org.opennms.repo.impl.actions.CloneAction;
import org.opennms.repo.impl.rpm.RPMRepository;

public class CloneActionTest {
	private static final Path repositoryRoot = Paths.get("target/commands/clone/repositories");
	private static GPGInfo s_gpginfo;

	@BeforeClass
	public static void generateGPG() throws Exception {
		s_gpginfo = TestUtils.generateGPGInfo();
	}

	@Before
	public void setUp() throws Exception {
		Util.recursiveDelete(Paths.get("target/commands/clone"));
	}

	@Test
	public void testCloneRPMRepository() throws Exception {
		final Path sourceRoot = repositoryRoot.resolve("testCloneRPMRepository").resolve("source").normalize().toAbsolutePath();
		final Path targetRoot = sourceRoot.resolve("../target").normalize().toAbsolutePath();
		final RPMRepository sourceRepo = new RPMRepository(sourceRoot);
		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), sourceRoot.toFile());
		sourceRepo.index(s_gpginfo);
		assertTrue(sourceRepo.getRoot().toFile().exists());
		assertTrue(sourceRepo.getRoot().resolve(TestUtils.A1_X64_FILENAME).toFile().exists());

		final CloneAction command = new CloneAction(new Options("clone"), Arrays.asList(sourceRoot.toString(), targetRoot.toString()));
		command.run();

		// make sure the source repo is still the same
		assertTrue(sourceRepo.getRoot().toFile().exists());
		assertTrue(sourceRepo.getRoot().resolve(TestUtils.A1_X64_FILENAME).toFile().exists());

		final RPMRepository targetRepo = new RPMRepository(targetRoot);
		assertNotNull(targetRepo);
		assertFalse("source repo had no parent, so the target should have none either.", targetRepo.hasParent());
		assertTrue(targetRepo.getRoot().toFile().exists());
		assertTrue(targetRepo.getRoot().resolve(TestUtils.A1_X64_FILENAME).toFile().exists());
	}

	@Test
	public void testCloneRPMRepositoryWithParent() throws Exception {
		final Path parentRoot = repositoryRoot.resolve("testCloneRPMRepositoryWithParent").resolve("parent").normalize().toAbsolutePath();
		final Path sourceRoot = parentRoot.resolve("../source").normalize().toAbsolutePath();
		final Path targetRoot = sourceRoot.resolve("../target").normalize().toAbsolutePath();

		FileUtils.copyFileToDirectory(TestUtils.A1_X64_PATH.toFile(), parentRoot.toFile());
		FileUtils.copyFileToDirectory(TestUtils.A2_X64_PATH.toFile(), sourceRoot.toFile());

		final RPMRepository parentRepo = new RPMRepository(parentRoot);
		parentRepo.index();
		assertTrue(parentRepo.getRoot().toFile().exists());
		assertTrue(parentRepo.getRoot().resolve(TestUtils.A1_X64_FILENAME).toFile().exists());
		assertFalse(parentRepo.hasParent());

		final RPMRepository sourceRepo = new RPMRepository(sourceRoot, Util.newSortedSet(parentRepo));
		sourceRepo.index(s_gpginfo);
		assertTrue(sourceRepo.getRoot().toFile().exists());
		assertTrue(sourceRepo.getRoot().resolve(TestUtils.A2_X64_FILENAME).toFile().exists());
		assertTrue(sourceRepo.hasParent());

		final CloneAction command = new CloneAction(new Options("clone"), Arrays.asList(sourceRoot.toString(), targetRoot.toString()));
		command.run();

		// make sure the source repo is still the same
		assertTrue(sourceRepo.getRoot().toFile().exists());
		assertTrue(sourceRepo.getRoot().resolve(TestUtils.A2_X64_FILENAME).toFile().exists());

		final RPMRepository targetRepo = new RPMRepository(targetRoot);
		assertNotNull(targetRepo);
		assertTrue("target repo should have parent", targetRepo.hasParent());
		assertEquals("target repo parent should match source", parentRepo, targetRepo.getParents().first());
		assertTrue(targetRepo.getRoot().toFile().exists());
		assertTrue(targetRepo.getRoot().resolve(TestUtils.A2_X64_FILENAME).toFile().exists());
	}
}
