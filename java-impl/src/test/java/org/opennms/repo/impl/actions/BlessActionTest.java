package org.opennms.repo.impl.actions;

import static org.junit.Assert.*;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;

import org.apache.commons.io.FileUtils;
import org.junit.Before;
import org.junit.BeforeClass;
import org.junit.Ignore;
import org.junit.Test;
import org.opennms.repo.api.GPGInfo;
import org.opennms.repo.api.RepositoryMetadata;
import org.opennms.repo.api.Util;
import org.opennms.repo.impl.Options;
import org.opennms.repo.impl.TestUtils;
import org.opennms.repo.impl.actions.BlessAction;
import org.opennms.repo.impl.rpm.RPMMetaRepository;
import org.opennms.repo.impl.rpm.RPMRepository;

public class BlessActionTest {
	private static final Path repositoryRoot = Paths.get("target/commands/bless/repositories");
	private static GPGInfo s_gpginfo;

	@BeforeClass
	public static void generateGPG() throws Exception {
		s_gpginfo = TestUtils.generateGPGInfo();
	}

	@Before
	public void setUp() throws Exception {
		Util.recursiveDelete(Paths.get("target/commands/bless"));
	}

	@Test
	public void testBlessRPMRepository() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testBlessRPMRepository").normalize().toAbsolutePath();
		Files.createDirectories(testRoot);

		final BlessAction command = new BlessAction(new Options("bless"), Arrays.asList(testRoot.toString()));
		command.run();
		
		final RepositoryMetadata metadata = RepositoryMetadata.getInstance(testRoot);
		assertNotNull(metadata);
		assertEquals(testRoot, metadata.getRoot().normalize().toAbsolutePath());

		assertEquals(RPMRepository.class, metadata.getRepositoryInstance().getClass());
	}

	@Test
	public void testBlessRPMRepositoryWithName() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testBlessRPMRepositoryWithName").normalize().toAbsolutePath();
		Files.createDirectories(testRoot);

		final BlessAction command = new BlessAction(new Options("bless"), Arrays.asList(testRoot.toString(), "blah"));
		command.run();
		
		final RepositoryMetadata metadata = RepositoryMetadata.getInstance(testRoot);
		assertNotNull(metadata);
		assertEquals(testRoot, metadata.getRoot().normalize().toAbsolutePath());
		assertEquals("blah", metadata.getName());

		assertEquals(RPMRepository.class, metadata.getRepositoryInstance().getClass());
	}


	@Test
	public void testBlessRPMMetaRepository() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testBlessRPMMetaRepository").normalize().toAbsolutePath();
		Files.createDirectories(testRoot.resolve("common").resolve("repodata"));

		final BlessAction command = new BlessAction(new Options("bless"), Arrays.asList(testRoot.toString()));
		command.run();
		
		final RepositoryMetadata metadata = RepositoryMetadata.getInstance(testRoot);
		assertNotNull(metadata);
		assertEquals(testRoot, metadata.getRoot().normalize().toAbsolutePath());
		
		assertEquals(RPMMetaRepository.class, metadata.getRepositoryInstance().getClass());
	}

	@Test
	public void testBlessRPMMetaRepositoryWithName() throws Exception {
		final Path testRoot = repositoryRoot.resolve("testBlessRPMMetaRepositoryWithName").normalize().toAbsolutePath();
		Files.createDirectories(testRoot.resolve("common").resolve("repodata"));

		final BlessAction command = new BlessAction(new Options("bless"), Arrays.asList(testRoot.toString(), "blah"));
		command.run();
		
		final RepositoryMetadata metadata = RepositoryMetadata.getInstance(testRoot);
		assertNotNull(metadata);
		assertEquals(testRoot, metadata.getRoot().normalize().toAbsolutePath());
		assertEquals("blah", metadata.getName());

		assertEquals(RPMMetaRepository.class, metadata.getRepositoryInstance().getClass());
	}

}
