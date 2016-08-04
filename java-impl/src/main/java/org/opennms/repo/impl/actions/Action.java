package org.opennms.repo.impl.actions;

import java.io.PrintStream;
import java.util.Collection;

import org.apache.commons.lang3.text.WordUtils;
import org.reflections.Reflections;
import org.slf4j.LoggerFactory;

public interface Action {
	public String getDescription();

	public void run() throws ActionException;

	public void printUsage(PrintStream out);

	public static Class<? extends Action> getAction(final String action) {
		final String className = Action.class.getPackage().getName() + "." + WordUtils.capitalize(action) + "Action";
		try {
			return Class.forName(className).asSubclass(Action.class);
		} catch (ClassNotFoundException e) {
			LoggerFactory.getLogger(Action.class).warn("Unable to find class {} for action {}", className, action);
			return null;
		}
	}

	public static Collection<Class<? extends Action>> getActions() {
		final Reflections reflections = new Reflections(Action.class.getPackage().getName());
		return reflections.getSubTypesOf(Action.class);
	}
}
