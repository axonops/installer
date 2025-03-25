#!/bin/bash -e

# Load configurations from config.env
source config.env

install_java() {
    [ "$JAVA_PKG" == "" ] || dnf install -y ${JAVA_PKG}
}

# Ensure the group exists
ensure_group_exists() {
    local group_name=$1
    if ! getent group $group_name > /dev/null 2>&1; then
        groupadd $group_name
    fi
}

# Ensure the user exists
ensure_user_exists() {
    local user_name=$1
    local group_name=$2
    if ! id -u $user_name > /dev/null 2>&1; then
        useradd -g $group_name $user_name
    fi
}

install_elasticsearch_tar() {
    local version=${ELASTICSEARCH_VERSION:-7.17.16}
    local url=${ELASTICSEARCH_TAR}
    local install_dir=${ELASTICSEARCH_INSTALL_DIR:-/opt/elasticsearch}

    echo "Downloading Elasticsearch version $version..."
    wget $url -O elasticsearch-$version.tar.gz

    echo "Installing Elasticsearch..."
    mkdir -p $install_dir
    tar -xzf elasticsearch-$version.tar.gz -C $install_dir --strip-components=1

    echo "Elasticsearch $version installed in $install_dir"
}

install_elasticsearch_rpm() {
    rpm -Uvh ${ELASTICSEARCH_RPM}
}

install_elasticsearch() {
    if [[ "${ELASTICSEARCH_INSTALLATION_METHOD}" == "tar" ]]; then
        install_elasticsearch_tar
    else
        install_elasticsearch_rpm
    fi
}

configure_elasticsearch() {
    if [[ "${ELASTICSEARCH_INSTALLATION_METHOD}" == "tar" ]]; then
        local config_file="${ELASTICSEARCH_INSTALL_DIR}/config/elasticsearch.yml"
    else
        local config_file="/etc/elasticsearch/elasticsearch.yml"
    fi
    
    local network_host=${ELASTICSEARCH_NETWORK_HOST:-127.0.0.1}

    echo "Configuring Elasticsearch to listen on $network_host..."
    echo "network.host: $network_host" >> $config_file
    echo 'thread_pool.write.queue_size: 2000' >> /etc/elasticsearch/elasticsearch.yml

    echo "Elasticsearch configuration updated."

    systemctl enable elasticsearch
    systemctl restart elasticsearch
}

install_cassandra() {
    local version=${CASSANDRA_VERSION:-4.1.7}
    local url=${CASSANDRA_TAR_URL:-http://downloads.apache.org/dist/cassandra/$version/apache-cassandra-$version-bin.tar.gz}
    local install_dir=${CASSANDRA_INSTALL_DIR:-/opt/cassandra}

    echo "Downloading Apache Cassandra version $version..."
    wget $url -O apache-cassandra-$version-bin.tar.gz

    echo "Installing Apache Cassandra..."
    mkdir -p $install_dir
    tar -xzf apache-cassandra-$version-bin.tar.gz -C $install_dir --strip-components=1

    echo "Apache Cassandra $version installed in $install_dir"
}

configure_cassandra() {
    local config_file="${CASSANDRA_INSTALL_DIR}/conf/cassandra.yaml"
    local listen_address=${CASSANDRA_LISTEN_ADDRESS:-127.0.0.1}
    local dc=${CASSANDRA_DC:-axonops}
    local rack=${CASSANDRA_RACK:-rack1}

    echo "Configuring Apache Cassandra to listen on $listen_address..."
    sed -i "s/^listen_address:.*/listen_address: $listen_address/" $config_file

    echo "Setting Cassandra data center to $dc and rack to $rack..."
    echo "dc: $dc" >> $config_file
    echo "rack: $rack" >> $config_file

    echo "Apache Cassandra configuration updated."
}

install_axonops_server_local() {
    rpm -Uvh ${AXONOPS_SERVER_RPM}
}

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

install_axonops_server_remote() {
    local version=${AXONOPS_SERVER_VERSION:-latest}
    if [ "$version" == "latest" ]; then
        pkg="axonops-server"
    else
        pkg="axonops-server-${version}"
    fi

    setup_axonops_repo

    dnf install -y $pkg
}

install_axonops_server() {
    if [[ "${AXONOPS_SERVER_RPM}" == "" ]]; then
        install_axonops_server_remote
    else
        install_axonops_server_local
    fi
    systemctl enable axonops
    systemctl start axonops
}

install_axonops_dash_local() {
    rpm -Uvh ${AXONOPS_DASH_SERVER_RPM}
}

install_axonops_dash_remote() {
    local version=${AXONOPS_DASH_VERSION:-latest}
    if [ "$version" == "latest" ]; then
        pkg="axon-dash"
    else
        pkg="axon-dash-${version}"
    fi

    setup_axonops_repo

    dnf install -y $pkg
}

install_axonops_dash() {
    if [[ "${AXONOPS_DASH_SERVER_RPM}" == "" ]]; then
        install_axonops_dash_remote
    else
        install_axonops_dash_local
    fi
    dnf -y install fuse
    systemctl enable axon-dash
    systemctl start axon-dash
}

# Call the function to install Elasticsearch if enabled
if [[ "${ENABLE_ELASTICSEARCH}" == "true" ]]; then
    install_java
    ensure_group_exists "elasticsearch"
    ensure_user_exists "elasticsearch" "elasticsearch"
    install_elasticsearch
    configure_elasticsearch
fi

# Call the function to install Apache Cassandra if enabled
if [[ "${ENABLE_CASSANDRA}" == "true" ]]; then
    install_java
    ensure_group_exists "cassandra"
    ensure_user_exists "cassandra" "cassandra"
    install_cassandra
    configure_cassandra
fi

# Call the function to install AxonOps server
install_axonops_server

# Call the function to install AxonOps dashboard
install_axonops_dash
