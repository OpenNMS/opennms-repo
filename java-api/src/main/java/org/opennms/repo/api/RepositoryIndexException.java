package org.opennms.repo.api;

public class RepositoryIndexException extends RepositoryException {
    private static final long serialVersionUID = 1L;

    public RepositoryIndexException() {
        super();
    }

    public RepositoryIndexException(final String message) {
        super(message);
    }

    public RepositoryIndexException(final Throwable cause) {
        super(cause);
    }

    public RepositoryIndexException(final String message, final Throwable cause) {
        super(message, cause);
    }

    public RepositoryIndexException(final String message, final Throwable cause, final boolean enableSuppression, final boolean writableStackTrace) {
        super(message, cause, enableSuppression, writableStackTrace);
    }
}
