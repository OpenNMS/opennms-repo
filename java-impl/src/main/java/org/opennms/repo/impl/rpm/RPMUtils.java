package org.opennms.repo.impl.rpm;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.List;
import java.util.SortedSet;
import java.util.TreeSet;

import org.opennms.repo.api.RepositoryException;
import org.opennms.repo.api.RepositoryPackage.Architecture;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class RPMUtils {
    private static final Logger LOG = LoggerFactory.getLogger(RPMUtils.class);

    private RPMUtils() {
    }

    public static RPMPackage getPackage(final File rpmFile) {
        final Path rpmPath = rpmFile.toPath().normalize().toAbsolutePath();
        final RPMCommand command = new RPMCommand(rpmPath).query("%{name}|%{epoch}|%{version}|%{release}|%{arch}");
        command.run();
        final List<String> output = command.getOutput();
        if (output.size() < 1) {
            LOG.debug("Unable to get output from RPM query on {}", rpmFile);
            LOG.debug("STDERR was: {}", command.getErrorOutput());
            throw new IllegalStateException("Unable to get output from RPM query on " + rpmFile);
        }
        final String[] entries = output.get(0).split("\\|");
        final String rpmName = entries[0];
        final String epochString = entries[1];
        final String version = entries[2];
        final String release = entries[3];
        final String archString = entries[4];

        final Integer epoch = "(none)".equals(epochString)? 0 : Integer.valueOf(epochString);
        Architecture arch = null;
        if ("x86_64".equals(archString)) {
            arch = Architecture.AMD64;
        } else if (archString.matches("^i[3456]86$")) {
            arch = Architecture.I386;
        } else if ("noarch".equals(archString)) {
            arch = Architecture.ALL;
        }
        return new RPMPackage(rpmName, new RPMVersion(epoch, version, release), arch, rpmPath);
    }

    public static File generateDelta(final File rpmFrom, final File rpmTo) {
        return RPMUtils.generateDelta(rpmFrom, rpmTo, null);
    }

    public static File generateDelta(final File rpmFromFile, final File rpmToFile, final File rpmOutFile) {
        assert(rpmFromFile != null);
        assert(rpmToFile != null);

        final RPMPackage rpmFrom = RPMUtils.getPackage(rpmFromFile);
        final RPMPackage rpmTo = RPMUtils.getPackage(rpmToFile);
        final MakeDeltaRPMCommand command;
        if (rpmFrom.compareTo(rpmTo) == -1) {
            command = new MakeDeltaRPMCommand(rpmFrom, rpmTo, rpmOutFile == null? null:rpmOutFile.toPath());
        } else {
            command = new MakeDeltaRPMCommand(rpmTo, rpmFrom, rpmOutFile == null? null:rpmOutFile.toPath());
        }
        command.run();
        final File outputFile = command.getOutputRPMPath().toFile();
        if (outputFile == null || !outputFile.exists()) {
            throw new IllegalStateException("makedeltarpm has not created a delta!");
        }
        return outputFile;
    }

    public static void generateDeltas(final File root) {
        final SortedSet<RPMPackage> rpms = new TreeSet<RPMPackage>();
        final File deltaDir = new File(root, "drpms");

        try {
            Files.walk(root.toPath().normalize().toAbsolutePath()).forEach(path -> {
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
        
        LOG.debug("RPMs: {}", rpms);
        RPMPackage previous = null;
        for (final RPMPackage rpm : rpms) {
            if (previous != null && previous.getName().equals(rpm.getName())) {
                LOG.trace("Same package: '{}' and '{}'", previous, rpm);
                final String deltaName = RPMUtils.getDeltaFileName(previous, rpm);
                final File deltaRPMFile = new File(deltaDir, deltaName);
                boolean generate = false;
                if (!deltaRPMFile.exists()) {
                    generate = true;
                    LOG.trace("drpm does not exist: {}", deltaName);
                } else {
                    try {
                        final BasicFileAttributes drpmAttr = Files.readAttributes(deltaRPMFile.toPath(), BasicFileAttributes.class);
                        final BasicFileAttributes previousAttr = Files.readAttributes(previous.getPath(), BasicFileAttributes.class);
                        final BasicFileAttributes rpmAttr = Files.readAttributes(rpm.getPath(), BasicFileAttributes.class);
                        if (drpmAttr.creationTime().compareTo(previousAttr.creationTime()) == -1) {
                            LOG.debug("drpm {} is older than {}", deltaName, previous);
                            generate = true;
                        } else if (drpmAttr.creationTime().compareTo(rpmAttr.creationTime()) == -1) {
                            LOG.debug("drpm {} is older than {}", deltaName, rpm);
                            generate = true;
                        } else {
                            LOG.debug("drpm {} is up-to-date", deltaName);
                        }
                    } catch (final Exception e) {
                        LOG.debug("Failed to read attributes from files.  Generating anyways.", e);
                        generate = true;
                    }
                }
                if (generate) {
                    LOG.trace("generating {}", deltaName);
                    RPMUtils.generateDelta(previous.getFile(), rpm.getFile(), deltaRPMFile);
                } else {
                    LOG.trace("NOT generating {}", deltaName);
                }
            }
            previous = rpm;
        }
    }

    public static String getDeltaFileName(final File fromRPMFile, final File toRPMFile) {
        return getDeltaFileName(RPMUtils.getPackage(fromRPMFile), RPMUtils.getPackage(toRPMFile));
    }

    public static String getDeltaFileName(final RPMPackage fromRPM, final RPMPackage toRPM) {
        final StringBuilder sb = new StringBuilder();
        sb.append(fromRPM.getName()).append("-");
        sb.append(fromRPM.getVersion().toStringWithoutEpoch()).append("_");
        sb.append(toRPM.getVersion().toStringWithoutEpoch()).append(".");
        sb.append(fromRPM.getArchitectureString()).append(".drpm");
        return sb.toString();
    }
}
