## Comparison between Kernel and Userspace QUIC implementations
This work focuses on comparing linux kernel-space implementations of the QUIC protocol with user-space implementations, aiming to evaluate the performance differences in terms of goodput and system calls.

## Getting started

Build and install the [QUIC Linux Module](https://github.com/lxin/quic):

```sh
sudo apt install make autoconf automake libtool pkg-config gnutls-dev linux-headers-$(uname -r) -y
git clone https://github.com/lxin/quic
cd quic/
./autogen.sh
autoreconf -i
./configure --prefix=/usr
make
sudo make install
```

Install the necessary tools:

- `docker`
- `docker compose`
- `bpftrace`
- `tshark`
- `jq`

Build the linuxquic image:

```sh
git clone https://github.com/quic-interop/quic-network-simulator && cd quic-network-simulator/
cp -r ../quic/tests/interop linuxquic
CLIENT="linuxquic" SERVER="linuxquic" docker compose build
```

Run the test script:

```sh
git clone https://github.com/BrunoBarrosXavier/QUIC-kernel-vs-userspace 
cd QUIC-kernel-vs-userspace/
sudo bash ./run.sh
```
