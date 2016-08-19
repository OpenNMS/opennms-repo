package org.opennms.repo.impl.rpm;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.SortedSet;
import java.util.TreeSet;

import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryPackage.Architecture;
import org.opennms.repo.api.Util;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class RPMUtils {
	private static final Logger LOG = LoggerFactory.getLogger(RPMUtils.class);

	private RPMUtils() {
	}

	public static RPMPackage getPackage(final File rpmFile) {
		final Path rpmPath = rpmFile.toPath().normalize().toAbsolutePath();
		return RPMUtils.getPackage(rpmPath);
	}

	public static RPMPackage getPackage(final Path rpmPath) {
		if (!rpmPath.toFile().exists()) {
			throw new IllegalArgumentException("Unable to query RPM information for nonexistent file: " + rpmPath);
		}
		final RPMCommand command = new RPMCommand(rpmPath).query("%{name}|%{epoch}|%{version}|%{release}|%{arch}|%{sourcepackage}");
		command.run();
		final List<String> output = command.getOutput();
		if (output.size() < 1) {
			LOG.debug("Unable to get output from RPM query on {}", rpmPath);
			LOG.debug("STDERR was: {}", command.getErrorOutput());
			throw new IllegalStateException("Unable to get output from RPM query on " + Util.relativize(rpmPath));
		}
		final String[] entries = output.get(0).split("\\|");
		final String rpmName = entries[0];
		final String epochString = entries[1];
		final String version = entries[2];
		final String release = entries[3];
		final String archString = entries[4];
		final String sourcePackageString = entries[5];

		LOG.debug("Parsed RPM {}: {}", Util.relativize(rpmPath), Arrays.asList(entries));
		final Integer epoch = "(none)".equals(epochString) ? 0 : Integer.valueOf(epochString);
		Architecture arch = null;
		if ("x86_64".equals(archString)) {
			arch = Architecture.AMD64;
		} else if (archString.matches("^i[3456]86$")) {
			arch = Architecture.I386;
		} else if ("noarch".equals(archString)) {
			arch = Architecture.ALL;
		}
		if ("1".equals(sourcePackageString)) {
			arch = Architecture.SOURCE;
		}
		return new RPMPackage(rpmName, new RPMVersion(epoch, version, release), arch, rpmPath);
	}

	public static File generateDelta(final File rpmFromFile, final File rpmToFile, final File rpmOutFile) {
		assert (rpmFromFile != null);
		assert (rpmToFile != null);

		if (!rpmFromFile.exists()) {
			throw new IllegalArgumentException("File does not exist: " + rpmFromFile);
		}
		if (!rpmToFile.exists()) {
			throw new IllegalArgumentException("File does not exist: " + rpmToFile);
		}
		final RPMPackage rpmFrom = RPMUtils.getPackage(rpmFromFile);
		final RPMPackage rpmTo = RPMUtils.getPackage(rpmToFile);
		final MakeDeltaRPMCommand command;
		if (rpmFrom.compareTo(rpmTo) == -1) {
			command = new MakeDeltaRPMCommand(rpmFrom, rpmTo, rpmOutFile == null ? null : rpmOutFile.toPath());
		} else {
			command = new MakeDeltaRPMCommand(rpmTo, rpmFrom, rpmOutFile == null ? null : rpmOutFile.toPath());
		}
		LOG.debug("makedelta command = {}", command);
		command.run();
		final File outputFile = command.getOutputRPMPath().toFile();
		if (outputFile == null || !outputFile.exists()) {
			LOG.debug("STDOUT: {}", command.getOutput());
			LOG.debug("STDERR: {}", command.getErrorOutput());
			throw new IllegalStateException("makedeltarpm has not created a delta!");
		}
		return outputFile;
	}

	public static SortedSet<RPMPackage> getPackages(final Path root) {
		final SortedSet<RPMPackage> rpms = new TreeSet<RPMPackage>();

		try {
			Files.walk(root.normalize().toAbsolutePath()).forEach(path -> {
				if (path.toFile().isFile()) {
					if (path.toString().endsWith(".rpm")) {
						LOG.debug("found RPM: {}", path);
						rpms.add(RPMUtils.getPackage(path.toFile()));
					} else {
						LOG.trace("Not an RPM: {}", path);
					}
				}
			});
		} catch (final Exception e) {
			throw new RepositoryException("Unable to walk " + root + " for delta RPM generation.", e);
		}
		return rpms;
	}

	public static void generateDeltas(final File root) {
		final Path rootPath = root.toPath();
		final Path deltaPath = rootPath.resolve("drpms");

		final SortedSet<RPMPackage> rpms = getPackages(rootPath);
		LOG.debug("RPMs: {}", rpms);

		final Collection<DeltaRPM> deltas = getDeltas(rpms);
		LOG.debug("Deltas: {}", deltas);

		Util.getStream(deltas).forEach(drpm -> {
			final Path drpmPath = drpm.getFilePath(deltaPath);
			boolean generate = false;

			if (!drpmPath.toFile().exists()) {
				generate = true;
				LOG.trace("drpm does not exist: {}", Util.relativize(drpmPath));
			} else {
				try {
					final long drpmTime = Util.getFileTime(drpmPath).toMillis();
					final long fromTime = Util.getFileTime(drpm.getFromRPM().getPath()).toMillis();
					final long toTime = Util.getFileTime(drpm.getToRPM().getPath()).toMillis();

					// if the DRPM is older than the source RPMs, re-generate it
					generate = drpmTime < fromTime || drpmTime < toTime;
				} catch (final Exception e) {
					LOG.debug("Failed to read attributes from files.  Generating anyways.", e);
					generate = true;
				}
			}
			if (generate) {
				LOG.info("- generating {}", Util.relativize(drpmPath));
				try {
					RPMUtils.generateDelta(drpm.getFromRPM().getFile(), drpm.getToRPM().getFile(), drpmPath.toFile());
				} catch (final Exception e) {
					LOG.warn("Failed to generate delta RPM {}", drpm, e);
				}
			} else {
				LOG.trace("- NOT generating {}", drpm);
			}
		});
	}

	public static String getDeltaFileName(final File fromRPMFile, final File toRPMFile) {
		return new DeltaRPM(RPMUtils.getPackage(fromRPMFile), RPMUtils.getPackage(toRPMFile)).getFileName();
	}

	public static Collection<DeltaRPM> getDeltas(final Collection<RPMPackage> packageCollection) {
		LOG.debug("Getting deltas for package collection: {}", packageCollection);

		final SortedSet<RPMPackage> packages = new TreeSet<RPMPackage>(packageCollection);
		final List<DeltaRPM> drpms = new ArrayList<>();

		// first, calculate the "newest" version of each packageName.arch tuple
		final Map<String, RPMPackage> newest = getNewest(packages);

		// then, iterate over the packages and for each "old" package, create
		// a DeltaRPM from it to the newest
		for (final RPMPackage p : packages) {
			final RPMPackage newestPackage = newest.get(p.getNameKey());

			// don't delta a package to itself, you'll go blind ;)
			if (!p.equals(newestPackage)) {
				drpms.add(new DeltaRPM(p, newestPackage));
			}
		}

		return drpms;
	}

	public static Map<String, RPMPackage> getNewest(final SortedSet<RPMPackage> packages) {
		final Map<String, RPMPackage> newest = new HashMap<>();
		for (final RPMPackage p : packages) {
			newest.put(p.getNameKey(), p);
		}
		return newest;
	}
}
