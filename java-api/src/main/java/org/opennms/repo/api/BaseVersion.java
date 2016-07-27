package org.opennms.repo.api;

import java.util.Objects;

import org.opennms.repo.api.rpm.RPMVersionComparator;

public class BaseVersion implements Version, Comparable<Version> {
    private static final RPMVersionComparator s_comparator = new RPMVersionComparator();

    private final String m_version;
    private final String m_release;
    private final int m_epoch;

    public BaseVersion(final String version) {
        this(0, version, null);
    }

    public BaseVersion(final int epoch, final String version) {
        this(epoch, version, null);
    }

    public BaseVersion(final String version, final String release) {
        this(0, version, release);
    }

    public BaseVersion(final int epoch, final String version, final String release) {
        m_version = version;
        m_release = release;
        m_epoch = epoch;
    }

    @Override
    public int getEpoch() {
        return m_epoch;
    }

    @Override
    public String getVersion() {
        return m_version;
    }

    @Override
    public String getRelease() {
        return m_release;
    }

    @Override
    public boolean isValid() {
        return m_version != null && isValidVersionString();
    }

    private boolean isValidVersionString() {
        return m_version != null && !m_version.contains("-");
    }

    @Override
    public String toString() {
        final StringBuffer sb = new StringBuffer();
        if (m_epoch != 0) {
            sb.append(m_epoch).append(":");
        }
        sb.append(toStringWithoutEpoch());
        return sb.toString();
    }

    @Override
    public String toStringWithoutEpoch() {
        final StringBuffer sb = new StringBuffer();
        sb.append(m_version);
        if (m_release != null) {
            sb.append("-");
            sb.append(m_release);
        }
        return sb.toString();
    }

    @Override
    public final int compareTo(final Version that) {
        return _compareTo(that);
    }

    protected int _compareTo(final Version that) {
        if (that != null) {
            if (this == that) {
                return 0;
            }
            int ret = that.getEpoch() - this.getEpoch();
            if (ret == 0) {
                ret = s_comparator.compare(this.getVersion(), that.getVersion());
            }
            if (ret == 0) {
                final String thisRelease = this.getRelease();
                final String thatRelease = that.getRelease();
                if (thisRelease == null) {
                    if (thatRelease != null) {
                        ret = 1;
                    }
                } else if (thatRelease == null) {
                    ret = -1;
                } else {
                    ret = s_comparator.compare(this.getRelease(), thatRelease);
                }
            }
            return ret;
        }
        return 1;
    }

    @Override
    public int hashCode() {
        final int prime = 173;
        int result = 1;
        result = prime * result + m_epoch;
        result = prime * result + ((m_release == null) ? 0 : m_release.hashCode());
        result = prime * result + ((m_version == null) ? 0 : m_version.hashCode());
        return result;
    }

    @Override
    public boolean equals(final Object obj) {
        if (this == obj) {
            return true;
        }
        if (obj == null) {
            return false;
        }
        if (getClass() != obj.getClass()) {
            return false;
        }
        final BaseVersion that = (BaseVersion) obj;
        return Objects.equals(this.getEpoch(), that.getEpoch()) &&
                Objects.equals(this.getVersion(), that.getVersion()) &&
                Objects.equals(this.getRelease(), that.getRelease());
    }
}
