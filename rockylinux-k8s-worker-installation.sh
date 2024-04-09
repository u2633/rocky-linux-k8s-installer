#!/bin/bash
#
# This script file is just for the convenience of one-command depends on https://phoenixnap.com/kb/install-kubernetes-on-rocky-linux.
# The script contains two parts. One is for control plane and another is for work node. The difference is only on the firewall settings
# 
# Author: Zane Chen<zanechen.biz@gmail.com>
# Version: 1.0.0
# CHANGELOG:
#   - Init work node instllation script
#

### Install containerd ###
# Add the official Docker repository to your system. Docker does not maintain a separate repository for Rocky Linux, but the CentOS repo is fully compatible.
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Refresh the local repository information
sudo dnf makecache

# Install the containerd.io package
sudo dnf install -y containerd.io

# Back up the default configuration file for containerd
sudo mv /etc/containerd/config.toml /etc/containerd/config.toml.bak

# Create a new file with the default template
containerd config default > config.toml

# Find the SystemdCgroup field and change its value to true
sed -i 's/SystemdCgroup = true/SystemdCgroup = true/g' config.toml

# Place the new file in the /etc/containerd directory
sudo mv config.toml /etc/containerd/config.toml

# Enable the containerd service
sudo systemctl enable --now containerd.service

# Add the two modules required by the container runtime
sudo echo "overlay" >> /etc/modules-load.d/k8s.conf
sudo echo "br_netfilter" >> /etc/modules-load.d/k8s.conf

# Add the modules to the system using the modprobe command
sudo modprobe overlay
sudo modprobe br_netfilter

### Modify SELinux and Firewall Settings ###
# Change the SELinux mode to permissive with the setenforce command
sudo setenforce 0

# Make changes to the SELinux configuration
sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux

# Confirm the changes by checking the SELinux status
sestatus

# Add firewall exceptions to allow Kubernetes to communicate via dedicated ports. On the master node machine, execute the following commands
sudo firewall-cmd --permanent --add-port=179/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --permanent --add-port=4789/udp
sudo firewall-cmd --permanent --add-port=5473/tcp # Prevent clico node probe refused
sudo firewall-cmd --reload

### Configure Networking ###
# Kubernetes requires filtering and port forwarding enabled for packets going through a network bridge
sudo echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/k8s.conf
sudo echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/k8s.conf
sudo echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/k8s.conf
sudo sysctl --system

# Disable Swap
sudo swapoff -a
sudo sed -e '/swap/s/^/#/g' -i /etc/fstab

### Install Kubernetes Tools ###
# Create a repository file for Kubernetes
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Refresh the local repository cache
sudo dnf makecache

# Install the packages k8s needs
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet
