#!/bin/bash -e

# Load configurations from config.env
source config.env

install_java() {
    [ "$JAVA_PKG" == "" ] || dnf install -y ${JAVA_PKG}
}

create_elasticsearch_service() {
    cat > /etc/systemd/system/elasticsearch.service << EOL
Unit]
Description=Elasticsearch
Documentation=https://www.elastic.co
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
RuntimeDirectory=elasticsearch
PrivateTmp=true
Environment=ES_HOME=${ELASTICSEARCH_INSTALL_DIR:-/opt/elasticsearch}
Environment=ES_PATH_CONF=${ELASTICSEARCH_INSTALL_DIR:-/opt/elasticsearch}/config
Environment=PID_DIR=/run/elasticsearch
Environment=ES_SD_NOTIFY=true

WorkingDirectory=${ELASTICSEARCH_INSTALL_DIR:-/opt/elasticsearch}

User=elasticsearch
Group=elasticsearch

ExecStart=${ELASTICSEARCH_INSTALL_DIR:-/opt/elasticsearch}/bin/elasticsearch -p \${PID_DIR}/elasticsearch.pid --quiet

# StandardOutput is configured to redirect to journalctl since
# some error messages may be logged in standard output before
# elasticsearch logging system is initialized. Elasticsearch
# stores its logs in /var/log/elasticsearch and does not use
# journalctl by default. If you also want to enable journalctl
# logging, you can simply remove the "quiet" option from ExecStart.
StandardOutput=journal
StandardError=inherit

# Specifies the maximum file descriptor number that can be opened by this process
LimitNOFILE=65535

# Specifies the maximum number of processes
LimitNPROC=4096

# Specifies the maximum size of virtual memory
LimitAS=infinity

# Specifies the maximum file size
LimitFSIZE=infinity

# Disable timeout logic and wait until process is stopped
TimeoutStopSec=0

# SIGTERM signal is used to stop the Java process
KillSignal=SIGTERM

# Send the signal only to the JVM rather than its control group
KillMode=process

# Java process is never killed
SendSIGKILL=no

# When a JVM receives a SIGTERM signal it exits with code 143
SuccessExitStatus=143

# Allow a slow startup before the systemd notifier module kicks in to extend the timeout
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
EOL
    systemctl daemon-reload
    systemctl enable elasticsearch
}

install_elasticsearch_tar() {
    local version=${ELASTICSEARCH_VERSION:-7.17.16}
    local url=${ELASTICSEARCH_TAR}
    local install_dir=${ELASTICSEARCH_INSTALL_DIR:-/opt/elasticsearch}

    echo "Downloading Elasticsearch version $version..."
    wget $url -O elasticsearch-$version.tar.gz

    echo "Installing Elasticsearch..."
    [ -f $install_dir/bin/elasticsearch ] && return

    mkdir -p $install_dir
    tar -xzf elasticsearch-$version.tar.gz -C $install_dir --strip-components=1

    groupadd elasticsearch || /bin/true
    useradd -m -s /bin/bash -g elasticsearch elasticsearch || /bin/true
    # Fix permissions
    find $install_dir -type d -exec chmod 755 {} \;
    find $install_dir/config -type f -exec chmod 644 {} \;

    mkdir -p $install_dir/data
    chown -R elasticsearch:elasticsearch $install_dir/logs $install_dir/config $install_dir/data
    create_elasticsearch_service

    echo "Elasticsearch $version installed in $install_dir"
}

install_elasticsearch_rpm() {
    [ -x /usr/share/elasticsearch/bin/elasticsearch ] || rpm -Uvh ${ELASTICSEARCH_RPM}
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
        local config_dir="${ELASTICSEARCH_INSTALL_DIR}/config"
        local config_file="${ELASTICSEARCH_INSTALL_DIR}/config/elasticsearch.yml"
    else
        local config_file="/etc/elasticsearch/elasticsearch.yml"
        local config_dir="/etc/elasticsearch"
    fi
    
    local network_host=${ELASTICSEARCH_NETWORK_HOST:-127.0.0.1}

    echo "Configuring Elasticsearch to listen on $network_host..."
    grep -q network.host $config_file || echo "network.host: $network_host" >> $config_file
    grep -q thread_pool.write.queue_size $config_file || echo 'thread_pool.write.queue_size: 2000' >> ${config_dir}/elasticsearch.yml

    echo "-Xms${ELASTICSEARCH_HEAP:-512M}" > ${config_dir}/jvm.options.d/jvm.options
    echo "-Xmx${ELASTICSEARCH_HEAP:-512M}" >> ${config_dir}/jvm.options.d/jvm.options

    echo "Elasticsearch configuration updated."

    systemctl enable elasticsearch
    systemctl restart elasticsearch
}

install_cassandra() {
    local version=${CASSANDRA_VERSION:-4.1.8}
    local url=${CASSANDRA_TAR_URL:-http://downloads.apache.org/dist/cassandra/$version/apache-cassandra-$version-bin.tar.gz}
    local install_dir=${CASSANDRA_INSTALL_DIR:-/opt/cassandra}

    [ -f $install_dir/bin/cassandra ] && return

    echo "Downloading Apache Cassandra version $version..."
    wget $url -O apache-cassandra-$version-bin.tar.gz

    echo "Installing Apache Cassandra..."
    mkdir -p $install_dir
    tar -xzf apache-cassandra-$version-bin.tar.gz -C $install_dir --strip-components=1

    echo "Apache Cassandra $version installed in $install_dir"
}

create_cassandra_service() {
    cat > /etc/systemd/system/cassandra.service << EOL
[Unit]
Description=Cassandra
After=network.target

[Service]
User=cassandra
Group=cassandra
ExecStart=${CASSANDRA_INSTALL_DIR}/bin/cassandra -f -p /run/cassandra/cassandra.pid
StandardOutput=journal
StandardError=journal
LimitNOFILE=1000000
LimitMEMLOCK=infinity
LimitNPROC=32768
LimitAS=infinity
#Restart=always

[Install]
WantedBy=multi-user.target
EOL
}

configure_cassandra() {
    local config_file="${CASSANDRA_INSTALL_DIR}/conf/cassandra.yaml"
    local listen_address=${CASSANDRA_LISTEN_ADDRESS:-127.0.0.1}
    local dc=${CASSANDRA_DC:-axonops}
    local rack=${CASSANDRA_RACK:-rack1}

    echo "Configuring Apache Cassandra to listen on $listen_address..."
    sed -i "s/^listen_address:.*/listen_address: $listen_address/" $config_file

    echo "Setting Cassandra data center to $dc and rack to $rack..."
    sed -i ${CASSANDRA_INSTALL_DIR}/conf/cassandra-rackdc.properties -e "s/^dc=.*/dc=${dc}/"
    sed -i ${CASSANDRA_INSTALL_DIR}/conf/cassandra-rackdc.properties -e "s/^rack=.*/rack=${rack}/"
    sed -i ${CASSANDRA_INSTALL_DIR}/conf/cassandra.yaml -e "s/^endpoint_snitch: SimpleSnitch/endpoint_snitch: GossipingPropertyFileSnitch/"

    groupadd cassandra || /bin/true
    groupadd axonops || /bin/true
    useradd -m -s /bin/bash -g cassandra -G axonops cassandra || /bin/true
    useradd -m -s /bin/bash -g axonops -G cassandra axonops || /bin/true

    mkdir -p ${CASSANDRA_INSTALL_DIR}/{data,logs}
    chown -R cassandra:cassandra ${CASSANDRA_INSTALL_DIR}/{data,logs}

    create_cassandra_service

    echo "Apache Cassandra configuration updated."
    systemctl daemon-reload
    systemctl enable cassandra
    systemctl restart cassandra
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

configure_axonops_server() {
    cat > /etc/axonops/axon-server.yml << EOL
host: 0.0.0.0
api_port: 8080
agents_port: 1888
elastic_hosts:
  - ${AXONOPS_ELASTICSEARCH_URL:-http://localhost:9200}
tls:
  mode: "disabled"
EOL

    if [[ "${ENABLE_CASSANDRA}" == "true" ]]; then
        cat >> /etc/axonops/axon-server.yml << EOL
cql_hosts:
 - ${AXONOPS_CQL_HOST:-localhost:9042}
cql_username: "${AXONOPS_CQL_USERNAME:-cassandra}"
cql_password: "${AXONOPS_CQL_PASSWORD:-cassandra}"
cql_password: "cassandra"
cql_local_dc: "axonops"
cql_proto_version: 4
cql_max_searchqueriesparallelism: 100
cql_batch_size: 100
cql_page_size: 100
cql_cache_metrics: true
cql_autocreate_tables: true
cql_retrypolicy_numretries: 3
cql_retrypolicy_min: 1s
cql_retrypolicy_max: 10s
cql_reconnectionpolicy_maxretries: 10
cql_reconnectionpolicy_initialinterval: 1s
cql_reconnectionpolicy_maxinterval: 10s
cql_keyspace_replication: "{ 'class': 'NetworkTopologyStrategy', 'axonops': 1 }"
cql_metrics_cache_max_size: 2048  #MB
cql_metrics_cache_max_items : 100000
EOL
    fi
}

install_axonops_server_remote() {
    local version=${AXONOPS_SERVER_VERSION:-latest}
    if [ "$version" == "latest" ]; then
        pkg="axon-server"
    else
        pkg="axon-server-${version}"
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
    configure_axonops_server
    systemctl enable axon-server
    systemctl restart axon-server
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
    dnf -y install fuse

    if [[ "${AXONOPS_DASH_SERVER_RPM}" == "" ]]; then
        install_axonops_dash_remote
    else
        install_axonops_dash_local
    fi
    mkdir -p /etc/systemd/system/axon-dash.service.d && cat > /etc/systemd/system/axon-dash.service.d/override.conf << EOL
[Service]
ExecStart=
ExecStart=/usr/share/axonops/axon-dash --appimage-extract-and-run
EOL
    systemctl daemon-reload
    systemctl enable axon-dash
    systemctl start axon-dash
}

# Call the function to install Apache Cassandra if enabled
if [[ "${ENABLE_CASSANDRA}" == "true" ]]; then
    install_java
    install_cassandra
    configure_cassandra
fi

# Call the function to install Elasticsearch if enabled
if [[ "${ENABLE_ELASTICSEARCH}" == "true" ]]; then
    install_java
    install_elasticsearch
    configure_elasticsearch
fi

# Call the function to install AxonOps server
install_axonops_server

# Call the function to install AxonOps dashboard
install_axonops_dash
