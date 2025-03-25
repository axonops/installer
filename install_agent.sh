#!/bin/bash -e

# Load configurations from config.env
source config.env

setup_axonops_repo() {
    cat > /etc/yum.repos.d/axonops-yum.repo << EOL
[axonops-yum]
name=axonops-yum
baseurl=${AXONOPS_REPO_URL:-https://packages.axonops.com/yum/}
enabled=1
repo_gpgcheck=0
gpgcheck=0
EOL
}

install_axonops_agent_rpm() {
    rpm -Uvh ${AXONOPS_AGENT_RPM}
}

install_axonops_java_agent_rpm() {
    rpm -Uvh ${AXONOPS_AGENT_CASSANDRA_PKG}
}

install_axonops_agent_yum() {
    local version=${AXONOPS_AGENT_VERSION:-latest}
    if [ "$version" == "latest" ]; then
        pkg="axon-agent"
    else
        pkg="axon-agent-${version}"
    fi

    setup_axonops_repo

    dnf install -y $pkg
}

install_axonops_java_agent_yum() {
    local version=${AXONOPS_AGENT_CASSANDRA_PKG_VERSION:-latest}
    if [ "$version" == "latest" ]; then
        pkg="${AXONOPS_AGENT_CASSANDRA_PKG}"
    else
        pkg="${AXONOPS_AGENT_CASSANDRA_PKG}-${version}"
    fi

    dnf install -y $pkg
}

install_axonops_agent() {
    if [[ "${AXONOPS_AGENT_RPM}" == "" ]]; then
        install_axonops_agent_yum
    else
        install_axonops_agent_rpm
    fi
}

install_axonops_java_agent() {
    if [[ "${AXONOPS_AGENT_CASSANDRA_RPM}" == "" ]]; then
        install_axonops_java_agent_yum
    else
        install_axonops_java_agent_rpm
    fi
}

configure_axonops_agent() {
    cat > /etc/axonops/axon-agent.yml << EOL
axon-server:
    hosts: ${AXONOPS_SERVER_IP:-localhost}
    port: ${AXONOPS_SERVER_PORT:-1888}

axon-agent:
    org: "${AXONOPS_AGENT_ORG:-example}"
    tls:
      mode: "disabled" # disabled, TLS, mTLS
NTP:
    host: "pool.ntp.org" # Specify your NTP server IP address or hostname
    timeout: 6
EOL
    systemctl restart axon-agent
}

install_axonops_agent
install_axonops_java_agent
configure_axonops_agent

echo "Please add the following configuration to your Cassandra node and restart it when it is convenient."
echo
echo
echo JVM_OPTS="\$JVM_OPTS -javaagent:/usr/share/axonops/axon-cassandra4.1-agent.jar=/etc/axonops/axon-agent.yml"
echo
echo
