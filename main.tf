resource "google_service_account" "vm" {
  project      = var.project_id
  account_id   = "custom-compute"
  display_name = "Service Account for compute engine"
}

resource "google_project_iam_member" "vm_logs" {
  project            = var.project_id
  role               = "roles/logging.logWriter"
  member             = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_project_iam_member" "vm_metric" {
  project            = var.project_id
  role               = "roles/monitoring.metricWriter"
  member             = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_compute_instance" "core" {
  count = 1

  project      = var.project_id
  name         = "core-${count.index}"
  machine_type = "g1-small"
  zone         = "us-central1-a"

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
    preemptible       = true
    automatic_restart = false
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform", "logging-write", "monitoring-write"]
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
    siege \
    git \
    cron
ulimit -n 30000
ulimit -n 30000


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

git clone https://github.com/daredevil-ua/load-testing.git

cat <<EOF >> ./run.sh
#! /bin/bash

cd /load-testing
git pull
expressvpn disconnect
sleep 5
expressvpn connect "${var.vpn_location}"
siege -c 100 -t 27m -f /load-testing/target.txt
EOF

chmod +x ./run.sh

touch /var/log/run.log

(crontab -l ; echo '*/30 * * * * /usr/bin/sudo /run.sh >> /var/log/run.log 2>&1') | crontab -


curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
bash add-logging-agent-repo.sh --also-install

sudo tee /etc/google-fluentd/config.d/siege.conf <<EOF
<source>
    @type tail
    <parse>
        # 'none' indicates the log is unstructured (text).
        @type none
    </parse>
    # The path of the log file.
    path /var/log/run.log
    # The path of the position file that records where in the log file
    # we have processed already. This is useful when the agent
    # restarts.
    pos_file /var/lib/google-fluentd/pos/siege.pos
    read_from_head true
    # The log tag for this log input.
    tag siege
</source>
EOF
service google-fluentd restart

EOT
}