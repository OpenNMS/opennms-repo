package org.opennms.repo.impl;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.apache.commons.exec.CommandLine;
import org.apache.commons.exec.OS;

public abstract class Command extends CommandLine implements Runnable {
    public Command(final String executable) {
        super(which(executable));
    }

    public static String which(final String executable) {
        final String[] pathEntries;
        if (OS.isFamilyWindows()) {
            pathEntries = System.getenv("PATH").split(";");
        } else {
            pathEntries = System.getenv("PATH").split(":");
        }

        final List<String> searchPath = new ArrayList<>(Arrays.asList(pathEntries));
        searchPath.add("/usr/local/bin");
        searchPath.add("/usr/local/sbin");

        for (final String path : searchPath) {
            final Path exe = Paths.get(path).resolve(executable);
            if (exe.toFile().exists()) {
                return exe.toAbsolutePath().toString();
            }
        }

        return null;
    }

    public static Map<String,String> getEnvironment() {
        final Map<String,String> newenv = new HashMap<>(System.getenv());
        if (!OS.isFamilyWindows()) {
            newenv.put("PATH", newenv.get("PATH").concat(":/usr/local/bin:/usr/local/sbin"));
        }
        return newenv;
    }
}
