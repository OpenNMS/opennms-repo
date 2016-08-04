package org.opennms.repo.impl.actions;

import org.opennms.repo.api.RepositoryException;

public class ActionException extends RepositoryException {
	private static final long serialVersionUID = 1L;

	public ActionException() {
		super();
	}

	public ActionException(final String message) {
		super(message);
	}

	public ActionException(final Throwable cause) {
		super(cause);
	}

	public ActionException(final String message, final Throwable cause) {
		super(message, cause);
	}

	public ActionException(final String message, final Throwable cause, final boolean enableSuppression,
			final boolean writableStackTrace) {
		super(message, cause, enableSuppression, writableStackTrace);
	}

}
