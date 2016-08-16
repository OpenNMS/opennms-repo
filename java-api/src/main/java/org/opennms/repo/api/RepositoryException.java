package org.opennms.repo.api;

public class RepositoryException extends RuntimeException {
	private static final long serialVersionUID = 1L;

	public RepositoryException() {
		super();
	}

	public RepositoryException(final String message) {
		super(message);
	}

	public RepositoryException(final Throwable cause) {
		super(cause);
	}

	public RepositoryException(final String message, final Throwable cause) {
		super(message, cause);
	}

	public RepositoryException(final String message, final Throwable cause, final boolean enableSuppression, final boolean writableStackTrace) {
		super(message, cause, enableSuppression, writableStackTrace);
	}
}
