# #!/usr/bin/env bash

sudo apt install tshark jq bpftrace

if [[ ! -d quic ]]; then
    echo "Building QUIC Linux Module..."
    sudo apt install make autoconf automake libtool pkg-config gnutls-dev linux-headers-$(uname -r) -y
    git clone https://github.com/lxin/quic 
    pushd quic/ > /dev/null
    ./autogen.sh
    autoreconf -i
    ./configure --prefix=/usr
    make
    echo "Installing QUIC Linux Module..."
    sudo make install
	popd > /dev/null
fi

if [ ! -x "$(command -v docker)" ]; then
    echo "Installing Docker..."
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update

    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

    sudo reboot now
fi


if ! groups | grep -q 'docker'; then
    sudo groupadd docker
    sudo usermod -aG docker $USER
fi

if [[ ! -d quic-network-simulator ]]; then
    echo "Building linuxquic interop test..."
    git clone https://github.com/quic-interop/quic-network-simulator && cd quic-network-simulator/
    cp -r ../quic/tests/interop linuxquic
    CLIENT="linuxquic" SERVER="linuxquic" docker compose build
    cd ..
fi

