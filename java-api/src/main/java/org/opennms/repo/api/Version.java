package org.opennms.repo.api;

public interface Version extends Comparable<Version> {
    public int getEpoch();
    public String getVersion();
    public String getRelease();

    public boolean isValid();

    String toStringWithoutEpoch();
}
