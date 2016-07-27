package org.opennms.repo.api;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;
import java.nio.file.attribute.FileTime;

public abstract class PackageUtils {
    public static FileTime getFileTime(final Path filePath) throws IOException {
        final BasicFileAttributes repomdXmlAttrs = Files.readAttributes(filePath, BasicFileAttributes.class);
        final FileTime lastModified = repomdXmlAttrs.lastModifiedTime();
        final FileTime created = repomdXmlAttrs.creationTime();
        
        if (created.compareTo(lastModified) == 1) {
            return created;
        } else {
            return lastModified;
        }
    }

}
