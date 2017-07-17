FROM centos:7 AS maven
RUN yum -y install createrepo deltarpm
RUN yum -y install java-1.8.0-openjdk-devel
RUN yum -y install maven
RUN yum -y clean all
RUN echo $HOME
WORKDIR /opt/build
VOLUME [ "/opt/build" ]
