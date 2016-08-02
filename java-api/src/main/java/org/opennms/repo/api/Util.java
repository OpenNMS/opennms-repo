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
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ConcurrentHashMap;

import org.hudsonci.plugins.jna.PosixAPI;
import org.jruby.ext.posix.FileStat;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class Util {
	private static final Logger LOG = LoggerFactory.getLogger(Util.class);

    private Util() {}

    public static Path relativize(final Path path) {
        return Paths.get(".").normalize().toAbsolutePath().relativize(path.normalize().toAbsolutePath());
    }

    public static void recursiveDelete(final Path path) throws IOException {
        if (path.toFile().exists()) {
            //LOG.debug("path={}", path);
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
    	//LOG.debug("getFileTime({})", filePath);

    	// me love you
    	long time = 0;

    	try {
    		final FileStat stat = PosixAPI.get().stat(filePath.normalize().toString());
    		time = stat.ctime();
    		if (stat.mtime() > stat.ctime()) {
    			time = stat.mtime();
    		}
    		LOG.trace("getFileTime({}): {}", filePath, time);
    		return FileTime.fromMillis(time);
    	} catch (final Throwable t) {
    		LOG.debug("Failed to call native stat(), falling back to JVM BasicFileAttributes.", t);
    	}

    	final BasicFileAttributes fileAttrs = Files.readAttributes(filePath, BasicFileAttributes.class);
        final FileTime lastModified = fileAttrs.lastModifiedTime();
        final FileTime created = fileAttrs.creationTime();

        final FileTime ret = created.compareTo(lastModified) == 1? created : lastModified;
        LOG.trace("getFileTime({}): {}", filePath, ret);
        return ret;
    }

    public static Map<String,String> readMetadata(final Path path) throws IOException {
    	final Map<String,String> metadata = new ConcurrentHashMap<>();
    	final File metadataFile = path.resolve(Repository.REPO_METADATA_FILENAME).toFile();
    	if (metadataFile.exists()) {
        	try (final FileReader fr = new FileReader(metadataFile)) {
            	final Properties props = new Properties();
            	props.load(fr);
            	for (final Map.Entry<Object,Object> entry : props.entrySet()) {
            		final Object value = entry.getValue();
					metadata.put(entry.getKey().toString(), value == null? null : value.toString());
            	}
			}
    	}
    	return metadata;
    }

    public static void writeMetadata(final Map<String,String> metadata, final Path path) throws IOException {
    	final Properties props = new Properties();
    	for (final Map.Entry<String,String> entry : metadata.entrySet()) {
    		props.put(entry.getKey(), entry.getValue());
    	}
    	if (!path.toFile().exists()) {
    		Files.createDirectories(path);
    	}
    	try (final FileWriter fw = new FileWriter(path.resolve(Repository.REPO_METADATA_FILENAME).toFile())) {
        	props.store(fw, "Repository Metadata");
    	}
    }
}
