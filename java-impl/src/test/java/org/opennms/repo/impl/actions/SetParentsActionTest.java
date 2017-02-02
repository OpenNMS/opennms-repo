package org.opennms.repo.impl.actions;

import static org.junit.Assert.*;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Iterator;
import java.util.Set;

import org.apache.commons.io.FileUtils;
import org.junit.Before;
import org.junit.BeforeClass;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.Repository;
import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.Options;
import org.opennms.repo.impl.TestUtils;
import org.opennms.repo.impl.actions.SetParentsAction;
import org.opennms.repo.impl.rpm.RPMMetaRepository;
import org.opennms.repo.impl.rpm.RPMRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class SetParentsActionTest {
	private static final Logger LOG = LoggerFactory.getLogger(SetParentsActionTest.class);
	private static final Path repositoryRoot = Paths.get("target/commands/set-parents/repositories");
	private static GPGInfo s_gpginfo;

	@BeforeClass
	public static void generateGPG() throws Exception {
		s_gpginfo = TestUtils.generateGPGInfo();
	}

	@Before
	public void setUp() throws Exception {
		Util.recursiveDelete(repositoryRoot.getParent());
	}

	@Test
	public void testInvalidTarget() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testInvalidTarget");

		final Path parentRoot = testRoot.resolve("parent").normalize().toAbsolutePath();
		final RPMRepository parentRepo = new RPMRepository(parentRoot);
		parentRepo.index(s_gpginfo);

		final Path targetRoot = testRoot.resolve("target").normalize().toAbsolutePath();
		
		Exception ex = null;

		try {
			final SetParentsAction command = new SetParentsAction(new Options("set-parents"), Arrays.asList(targetRoot.toString(), parentRoot.toString()));
			command.run();
		} catch (final Exception e) {
			ex = e;
		}
		assertNotNull(ex);
		//LOG.debug("got exception:", ex);
		assertTrue(ex.getMessage(), ex.getMessage().contains("Target repository path"));

		ex = null;
		Files.createDirectories(targetRoot);
		try {
			final SetParentsAction command = new SetParentsAction(new Options("set-parents"), Arrays.asList(targetRoot.toString(), parentRoot.toString()));
			command.run();
		} catch (final Exception e) {
			ex = e;
		}
		assertNotNull(ex);
		//LOG.debug("got exception:", ex);
		assertTrue(ex.getMessage(), ex.getMessage().contains("but is invalid"));
	}

	@Test
	public void testInvalidParent() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testInvalidParent");

		final Path parentRoot = testRoot.resolve("parent").normalize().toAbsolutePath();
		final Path targetRoot = testRoot.resolve("target").normalize().toAbsolutePath();
		final RPMRepository targetRepo = new RPMRepository(targetRoot);
		targetRepo.index(s_gpginfo);
		
		Exception ex = null;
		try {
			final SetParentsAction command = new SetParentsAction(new Options("set-parents"), Arrays.asList(targetRoot.toString(), parentRoot.toString()));
			command.run();
		} catch (final Exception e) {
			ex = e;
		}
		assertNotNull(ex);
		//LOG.debug("got exception:", ex);
		assertTrue(ex.getMessage(), ex.getMessage().contains("Parent repository path"));

		ex = null;
		Files.createDirectories(parentRoot);
		try {
			final SetParentsAction command = new SetParentsAction(new Options("set-parents"), Arrays.asList(targetRoot.toString(), parentRoot.toString()));
			command.run();
		} catch (final Exception e) {
			ex = e;
		}
		assertNotNull(ex);
		//LOG.debug("got exception:", ex);
		assertTrue(ex.getMessage(), ex.getMessage().contains("but is invalid"));
	}

	@Test
	public void testMismatchedTypes() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testMismatchedTypes");

		final Path rpmRepoRoot = testRoot.resolve("rpm").normalize().toAbsolutePath();
		final RPMRepository rpmRepo = new RPMRepository(rpmRepoRoot);
		rpmRepo.index(s_gpginfo);

		final Path metaRepoRoot = testRoot.resolve("meta").normalize().toAbsolutePath();
		final RPMMetaRepository metaRepo = new RPMMetaRepository(metaRepoRoot);
		metaRepo.index(s_gpginfo);

		Exception ex = null;
		try {
			final SetParentsAction command = new SetParentsAction(new Options("set-parents"), Arrays.asList(metaRepoRoot.toString(), rpmRepoRoot.toString()));
			command.run();
		} catch (final Exception e) {
			ex = e;
		}
		assertNotNull(ex);
		//LOG.debug("got exception:", ex);
		assertTrue(ex.getMessage(), ex.getMessage().contains("does not match target repository"));

		ex = null;
		try {
			final SetParentsAction command = new SetParentsAction(new Options("set-parents"), Arrays.asList(rpmRepoRoot.toString(), metaRepoRoot.toString()));
			command.run();
		} catch (final Exception e) {
			ex = e;
		}
		assertNotNull(ex);
		//LOG.debug("got exception:", ex);
		assertTrue(ex.getMessage(), ex.getMessage().contains("does not match target repository"));

	}

	@Test
	public void testMismatchedParentTypes() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testMismatchedParentTypes");

		final Path targetRoot = testRoot.resolve("target").normalize().toAbsolutePath();
		final RPMRepository targetRepo = new RPMRepository(targetRoot);
		targetRepo.index(s_gpginfo);

		final Path rpmRepoRoot = testRoot.resolve("rpm").normalize().toAbsolutePath();
		final RPMRepository rpmRepo = new RPMRepository(rpmRepoRoot);
		rpmRepo.index(s_gpginfo);

		final Path metaRepoRoot = testRoot.resolve("meta").normalize().toAbsolutePath();
		final RPMMetaRepository metaRepo = new RPMMetaRepository(metaRepoRoot);
		metaRepo.index(s_gpginfo);

		Exception ex = null;
		try {
			final SetParentsAction command = new SetParentsAction(new Options("set-parents"), Arrays.asList(targetRoot.toString(), rpmRepoRoot.toString(), metaRepoRoot.toString()));
			command.run();
		} catch (final Exception e) {
			ex = e;
		}
		assertNotNull(ex);
		assertTrue(ex.getMessage(), ex.getMessage().contains("Multiple parent repositories specified, but their types don't match"));
	}

	@Test
	public void testSingleParent() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testSingleParent");

		final Path parentRoot = testRoot.resolve("parent").normalize().toAbsolutePath();
		final RPMRepository parentRepo = new RPMRepository(parentRoot);
		parentRepo.setName("parent");
		parentRepo.index(s_gpginfo);

		final Path targetRoot = testRoot.resolve("target").normalize().toAbsolutePath();
		final RPMRepository targetRepo = new RPMRepository(targetRoot);
		targetRepo.setName("target");
		targetRepo.index(s_gpginfo);
		
		Exception ex = null;
		try {
			final SetParentsAction command = new SetParentsAction(new Options("set-parents"), Arrays.asList(targetRoot.toString(), parentRoot.toString()));
			command.run();
		} catch (final Exception e) {
			ex = e;
		}
		assertNull(ex);
		
		final RepositoryMetadata metadata = RepositoryMetadata.getInstance(targetRoot);
		assertNotNull(metadata);
		assertEquals("target", metadata.getName());
		assertNotNull(metadata.getParentMetadata());
		assertEquals(1, metadata.getParentMetadata().size());
		assertEquals("parent", metadata.getParentMetadata().iterator().next().getName());
	}

	@Test
	public void testMultipleParents() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testMultipleParents");

		final Path parentARoot = testRoot.resolve("parent-a").normalize().toAbsolutePath();
		final RPMRepository parentARepo = new RPMRepository(parentARoot);
		parentARepo.setName("Parent A");
		parentARepo.index(s_gpginfo);

		final Path parentBRoot = testRoot.resolve("parent-b").normalize().toAbsolutePath();
		final RPMRepository parentBRepo = new RPMRepository(parentBRoot);
		parentBRepo.setName("Parent B");
		parentBRepo.index(s_gpginfo);

		final Path targetRoot = testRoot.resolve("target").normalize().toAbsolutePath();
		RPMRepository targetRepo = new RPMRepository(targetRoot);
		targetRepo.setName("target");
		targetRepo.index(s_gpginfo);
		
		Exception ex = null;
		try {
			final SetParentsAction command = new SetParentsAction(new Options("set-parents"), Arrays.asList(targetRoot.toString(), parentARoot.toString(), parentBRoot.toString()));
			command.run();
		} catch (final Exception e) {
			ex = e;
		}
		assertNull(ex);
 
		Files.walk(testRoot).sorted().forEach(path -> {
			System.err.println(path);
		});
		targetRepo = new RPMRepository(targetRoot);
		assertTrue(targetRepo.isValid());
		assertEquals("target", targetRepo.getName());
		final Set<Repository> parentRepos = targetRepo.getParents();
		assertNotNull(parentRepos);
		assertEquals(2, parentRepos.size());

		final Iterator<Repository> it = parentRepos.iterator();
		assertEquals("Parent A", it.next().getName());
		assertEquals("Parent B", it.next().getName());
	}
}
