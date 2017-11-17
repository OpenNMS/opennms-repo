package org.opennms.repo.api;

import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.BasicFileAttributes;
import java.nio.file.attribute.FileTime;
import java.util.Collection;
import java.util.Map;
import java.util.Properties;
import java.util.SortedSet;
import java.util.TreeSet;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Predicate;
import java.util.stream.Stream;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import jnr.posix.FileStat;
import jnr.posix.LinuxFileStat32;
import jnr.posix.LinuxFileStat64;
import jnr.posix.POSIX;
import jnr.posix.POSIXFactory;

public abstract class Util {
	private static final Logger LOG = LoggerFactory.getLogger(Util.class);
	private static volatile boolean m_enableParallel = true;

	private Util() {
	}

	public static Path relativize(final Path path) {
		return Paths.get(".").normalize().toAbsolutePath().relativize(path.normalize().toAbsolutePath());
	}

	public static void recursiveDelete(final Path path) throws IOException {
		if (path.toFile().exists()) {
			// LOG.debug("path={}", path);
			for (final File file : path.toFile().listFiles()) {
				if (file.isDirectory()) {
					recursiveDelete(file.toPath());
				} else {
					LOG.trace("delete: {}", file);
					file.delete();
				}
			}
			LOG.trace("delete: {}", path);
			Files.delete(path);
		}
	}

	public static FileTime getFileTime(final Path filePath) throws IOException {
		long ctime = -1;
		long mtime = -1;

		try {
			final POSIX posix = POSIXFactory.getNativePOSIX();
			final FileStat stat = posix.stat(filePath.normalize().toAbsolutePath().toString());
			ctime = stat.ctime() * 1000;
			mtime = stat.mtime() * 1000;
			if (posix.isNative()) {
				long ctimeNanoSecs = 0;
				long mtimeNanoSecs = 0;
				if (stat instanceof LinuxFileStat32) {
					final LinuxFileStat32 lfs = (LinuxFileStat32) stat;
					ctimeNanoSecs = lfs.cTimeNanoSecs();
					mtimeNanoSecs = lfs.mTimeNanoSecs();
				} else if (stat instanceof LinuxFileStat64) {
					final LinuxFileStat64 lfs = (LinuxFileStat64) stat;
					ctimeNanoSecs = lfs.cTimeNanoSecs();
					mtimeNanoSecs = lfs.mTimeNanoSecs();
				}
				ctime = Math.max(ctime, ctimeNanoSecs / 1000L);
				mtime = Math.max(mtime, mtimeNanoSecs / 1000L);
			}

			// me love you
			final long time = Math.max(ctime, mtime);

			LOG.trace("getFileTime({}): {}", filePath, time);
			return FileTime.fromMillis(time);
		} catch (final Throwable t) {
			LOG.debug("Failed to call native stat(), falling back to JVM BasicFileAttributes.", t);
		}

		final BasicFileAttributes fileAttrs = Files.readAttributes(filePath, BasicFileAttributes.class);
		final FileTime lastModified = fileAttrs.lastModifiedTime();
		final FileTime created = fileAttrs.creationTime();

		final FileTime ret = created.compareTo(lastModified) == 1 ? created : lastModified;
		LOG.trace("getFileTime({}): {}", filePath, ret);
		return ret;
	}

	public static Map<String, String> readMetadata(final Path path) throws IOException {
		final Map<String, String> metadata = new ConcurrentHashMap<>();
		final File metadataFile = path.resolve(Repository.REPO_METADATA_FILENAME).toFile();
		if (metadataFile.exists()) {
			try (final FileReader fr = new FileReader(metadataFile)) {
				final Properties props = new Properties();
				props.load(fr);
				for (final Map.Entry<Object, Object> entry : props.entrySet()) {
					final Object value = entry.getValue();
					metadata.put(entry.getKey().toString(), value == null ? null : value.toString());
				}
			}
		}
		return metadata;
	}

	public static void writeMetadata(final Map<String, String> metadata, final Path path) throws IOException {
		final Properties props = new Properties();
		for (final Map.Entry<String, String> entry : metadata.entrySet()) {
			props.put(entry.getKey(), entry.getValue());
		}
		if (!path.toFile().exists()) {
			Files.createDirectories(path);
		}
		try (final FileWriter fw = new FileWriter(path.resolve(Repository.REPO_METADATA_FILENAME).toFile())) {
			props.store(fw, "Repository Metadata");
		}
	}

	public static <T> SortedSet<T> newSortedSet(final Collection<T> items) {
		final SortedSet<T> sorted = new TreeSet<>(items);
		return sorted;
	}

	@SafeVarargs
	public static <T> SortedSet<T> newSortedSet(final T... items) {
		final SortedSet<T> sorted = new TreeSet<>();
		for (final T item : items) {
			sorted.add(item);
		}
		return sorted;
	}

	public static void enableParallel() {
		m_enableParallel = true;
	}

	public static void disableParallel() {
		m_enableParallel = false;
	}

	public static <T> Stream<T> getStream(Collection<T> coll) {
		if (m_enableParallel) {
			return coll.parallelStream();
		} else {
			return coll.stream();
		}
	}

	public static String getCollationName(final String name) {
		if (name.startsWith("jdk1.")) {
			// special case, "jdk1.8.0_60"
			return "jdk";
		} else if (name.startsWith("compat-")) {
			final String[] split = name.split("-");
			return split[0] + "-" + split[1];
		} else {
			final String[] split = name.split("-");
			return split[0];
		}
	}

	@SuppressWarnings("unchecked")
	public static Predicate<RepositoryPackage> combineFilters(final Predicate<RepositoryPackage>... predicates) {
		return Stream.of(predicates).reduce(x -> true, Predicate::and);
	}
}
