package org.opennms.repo.impl.rpm;

import java.util.Comparator;
import java.util.Iterator;
import java.util.SortedSet;

import org.opennms.repo.api.Repository;

public final class RepoSetComparator implements Comparator<SortedSet<? extends Repository>> {
	@Override
	public int compare(final SortedSet<? extends Repository> a, SortedSet<? extends Repository> b) {
		int ret = b.size() - a.size();
		final Iterator<? extends Repository> ait = a.iterator();
		final Iterator<? extends Repository> bit = b.iterator();
		if (ret == 0) {
			while (ait.hasNext() && bit.hasNext() && ret == 0) {
				final Repository arep = ait.next();
				final Repository brep = bit.next();
				ret = arep.compareTo(brep);
			}
		}
		if (ret == 0) {
			if (ait.hasNext()) {
				ret = -1;
			} else if (bit.hasNext()) {
				ret = 1;
			}
		}
		return ret;
	}
}