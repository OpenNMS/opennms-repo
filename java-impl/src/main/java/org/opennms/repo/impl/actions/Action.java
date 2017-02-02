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

	public static String getActionName(final Class<? extends Action> action) {
		return action.getSimpleName().replaceAll("([A-Z])", "-$1").replaceAll("Action$", "").replaceAll("^-",  "").replaceAll("-$", "").toLowerCase();
	}

	public static Class<? extends Action> getAction(final String actionText) {
		final StringBuilder action = new StringBuilder();
		for (final String chunk : actionText.split("-")) {
			action.append(WordUtils.capitalize(chunk));
		}
		final String className = Action.class.getPackage().getName() + "." + action.toString() + "Action";
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
