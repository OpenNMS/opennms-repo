package org.opennms.repo.api;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class Util {
    private static final Logger LOG = LoggerFactory.getLogger(Util.class);

    private Util() {}

    public static Path relativize(final Path path) {
        return Paths.get(".").toAbsolutePath().normalize().relativize(path);
    }

    public static void recursiveDelete(final Path path) throws IOException {
        if (path.toFile().exists()) {
            //LOG.debug("path={}", path);
            for (final File file : path.toFile().listFiles()) {
                if (file.isDirectory()) {
                    recursiveDelete(file.toPath());
                } else {
                    LOG.debug("delete: {}", file);
                    file.delete();
                }
            }
            //LOG.debug("delete: {}", path);
            Files.delete(path);
        }
    }
}
