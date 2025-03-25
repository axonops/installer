# AxonOps Installer

This repository contains scripts to install and configure AxonOps, Elasticsearch, and Apache Cassandra.

## Prerequisites

- CentOS/RHEL/RockyLinux 8-9 or compatible
- `dnf` package manager
- Internet connection to download packages or local yum mirrors

## Configuration

Before running the installer scripts, configure the environment variables in [./config.env](./config.env).

## Installation

### Install AxonOps Server and Dashboard

Run the `install_server.sh` script to install and configure AxonOps server, Elasticsearch, and Apache Cassandra:

### Install AxonOps Agent

Run the `install_agent.sh` script to install and configure the AxonOps agent:

## Usage

After installation, ensure that the services are running:

```bash
systemctl status axon-server
systemctl status axon-dash
systemctl status cassandra
systemctl status elasticsearch
systemctl status axon-agent
```

Refer to the respective service documentation for further configuration and usage details.