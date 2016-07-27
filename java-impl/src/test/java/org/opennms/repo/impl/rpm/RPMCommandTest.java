package org.opennms.repo.impl.rpm;

public class RPMCommandTest {

    public RPMCommandTest() {
        RPMCommand cmd = new RPMCommand();
        cmd.queryAll();
        cmd.run();
    }

}
