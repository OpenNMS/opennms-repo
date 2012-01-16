use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME                     => 'OpenNMS::Release',
    VERSION                  => '2.1.1',
    PREREQ_PM                => {
        'Expect'             => 1.20,
	'Net::SFTP::Foreign' => undef,
    },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM         => 'lib/OpenNMS/Release.pm', # retrieve abstract from module
       AUTHOR                => 'Benjamin Reed <ranger@opennms.org>') : ()),
);
