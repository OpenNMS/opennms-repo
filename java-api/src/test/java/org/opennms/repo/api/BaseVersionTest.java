package org.opennms.repo.api;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class BaseVersionTest {

    @Test
    public void testCreateInvalidVersions() {
        Version v = new BaseVersion(0, null, "1");
        assertFalse(v.isValid());
    }

    @Test
    public void testCreatValidVersions() {
        Version v = new BaseVersion("1.2.3");
        assertTrue(v.isValid());

        v = new BaseVersion(1, "1.2.3", "1");
        assertTrue(v.isValid());

        v = new BaseVersion("1.2.3", "1");
        assertTrue(v.isValid());
    }

    @Test
    public void testComparison() {
        Version a = new BaseVersion("1.0");
        Version b = new BaseVersion("1.1");

        assertEquals(0, a.compareTo(a));
        assertEquals(0, a.compareTo(new BaseVersion("1.0")));
        assertEquals(-1, a.compareTo(b));
        assertEquals(1, b.compareTo(a));

        b = new BaseVersion("1.0", "1");
        assertEquals(1, a.compareTo(b));
        assertEquals(-1, b.compareTo(a));

        a = new BaseVersion(0, "1.0");
        b = new BaseVersion(1, "0.9");
        assertEquals(0, a.compareTo(a));
        assertEquals(0, b.compareTo(b));
        assertEquals(1, a.compareTo(b));
        assertEquals(-1, b.compareTo(a));

        a = new BaseVersion("1.0");
        b = new BaseVersion("1.0.0");
        assertEquals(-1, a.compareTo(b));
        assertEquals(1, b.compareTo(a));

        a = new BaseVersion("1.0", "0.beta3");
        b = new BaseVersion("1.0alpha");
        assertEquals(-1, a.compareTo(b));
        assertEquals(1, b.compareTo(a));

        b = new BaseVersion("1.0", "beta.3");
        assertEquals(1, a.compareTo(b));
        assertEquals(-1, b.compareTo(a));

        b = new BaseVersion("1.0", "alpha4");
        assertEquals(1, a.compareTo(b));
        assertEquals(-1, b.compareTo(a));
    }

    @Test
    public void testToString() {
        assertEquals("1.0", new BaseVersion("1.0").toString());
        assertEquals("1.0.0", new BaseVersion("1.0.0").toString());        
        assertEquals("1.0-alpha4", new BaseVersion("1.0", "alpha4").toString());
        assertEquals("1:1.0-alpha4", new BaseVersion(1, "1.0", "alpha4").toString());
        assertEquals("1:1.0", new BaseVersion(1, "1.0", null).toString());
    } 
}
