#!/bin/bash -e

. $(ctx download-resource "components/utils")


export ERLANG_SOURCE_URL=$(ctx node properties erlang_rpm_source_url)  # (e.g. "http://www.rabbitmq.com/releases/erlang/erlang-17.4-1.el6.x86_64.rpm")
export RABBITMQ_SOURCE_URL=$(ctx node properties rabbitmq_rpm_source_url)  # (e.g. "http://www.rabbitmq.com/releases/rabbitmq-server/v3.5.3/rabbitmq-server-3.5.3-1.noarch.rpm")
export RABBITMQ_FD_LIMIT=$(ctx node properties rabbitmq_fd_limit)

export RABBITMQ_LOG_BASE="/var/log/cloudify/rabbitmq"

export RABBITMQ_USERNAME=$(ctx node properties rabbitmq_username)
export RABBITMQ_PASSWORD=$(ctx node properties rabbitmq_password)
export RABBITMQ_CERT_PUBLIC="$(ctx node properties rabbitmq_cert_public)"
export RABBITMQ_CERT_PRIVATE="$(ctx node properties rabbitmq_cert_private)"

ctx logger info "Installing RabbitMQ..."

copy_notice "rabbitmq"
create_dir "${RABBITMQ_LOG_BASE}"

yum_install ${ERLANG_SOURCE_URL}
yum_install ${RABBITMQ_SOURCE_URL}

# Dunno if required.. the key thing, that is... check please.
# curl --fail --location http://www.rabbitmq.com/releases/rabbitmq-server/v${RABBITMQ_VERSION}/rabbitmq-server-${RABBITMQ_VERSION}-1.noarch.rpm -o /tmp/rabbitmq.rpm
# sudo rpm --import https://www.rabbitmq.com/rabbitmq-signing-key-public.asc
# sudo yum install /tmp/rabbitmq.rpm -y

ctx logger info "Configuring logrotate..."
lconf="/etc/logrotate.d/rabbitmq-server"

cat << EOF | sudo tee $lconf > /dev/null
$RABBITMQ_LOG_BASE/*.log {
        daily
        missingok
        rotate 7
        compress
        delaycompress
        notifempty
        sharedscripts
        postrotate
            /sbin/service rabbitmq-server rotate-logs > /dev/null
        endscript
}
EOF

sudo chmod 644 $lconf

# Creating rabbitmq systemd stop script
cat << EOF | sudo tee /usr/local/bin/kill-rabbit > /dev/null
#! /usr/bin/env bash
for proc in "\$(/usr/bin/ps aux | /usr/bin/grep rabbitmq | /usr/bin/grep -v grep | /usr/bin/awk '{ print \$2 }')"; do
    /usr/bin/kill \${proc}
done
EOF
sudo chmod 500 /usr/local/bin/kill-rabbit

configure_systemd_service "rabbitmq"

ctx logger info "Configuring File Descriptors Limit..."
deploy_file "components/rabbitmq/config/rabbitmq_ulimit.conf" "/etc/security/limits.d/rabbitmq.conf"
replace "{{ ctx.node.properties.rabbitmq_fd_limit }}" ${RABBITMQ_FD_LIMIT} "/etc/security/limits.d/rabbitmq.conf"
replace "{{ ctx.node.properties.rabbitmq_fd_limit }}" ${RABBITMQ_FD_LIMIT} "/usr/lib/systemd/system/cloudify-rabbitmq.service"
sudo systemctl daemon-reload

ctx logger info "Chowning RabbitMQ logs path..."
sudo chown rabbitmq:rabbitmq ${RABBITMQ_LOG_BASE}

ctx logger info "Starting RabbitMQ Server in Daemonized mode..."
sudo systemctl start cloudify-rabbitmq.service

ctx logger info "Enabling RabbitMQ Plugins..."
run_command_with_retries "sudo rabbitmq-plugins enable rabbitmq_management"
run_command_with_retries "sudo rabbitmq-plugins enable rabbitmq_tracing"

ctx logger info "Disabling RabbitMQ guest user"
run_command_with_retries "sudo rabbitmqctl clear_permissions guest"
run_command_with_retries "sudo rabbitmqctl delete_user guest"

ctx logger info "Creating new RabbitMQ user and setting permissions"
run_command_with_retries sudo rabbitmqctl add_user ${RABBITMQ_USERNAME} ${RABBITMQ_PASSWORD}
run_noglob_command_with_retries sudo rabbitmqctl set_permissions ${RABBITMQ_USERNAME} '.*' '.*' '.*'

# Deploy certificates (if applicable)
# TODO: Validate that cert is in PEM format based on openssl command?
if [[ "${RABBITMQ_CERT_PRIVATE}" =~ "BEGIN RSA PRIVATE KEY" ]]; then
  ctx logger info "Found private certificate for rabbitmq."
  echo "${RABBITMQ_CERT_PRIVATE}" | sudo tee /etc/rabbitmq/rabbit-priv.pem >/dev/null
  # Only allow owner to see rabbit private cert
  sudo chmod 400 /etc/rabbitmq/rabbit-priv.pem
  sudo chown rabbitmq. /etc/rabbitmq/rabbit-priv.pem
else
  if [[ -z "${RABBITMQ_CERT_PRIVATE}" ]]; then
    ctx logger info "No private certificate found."
  else
    ctx logger warn "Private certificate did not appear to be in PEM format."
  fi
fi
# TODO: Validate that cert is in PEM format based on openssl command?
if [[ "${RABBITMQ_CERT_PUBLIC}" =~ "BEGIN CERTIFICATE" ]]; then
  ctx logger info "Found public certificate for rabbitmq."
  echo "${RABBITMQ_CERT_PUBLIC}" | sudo tee /etc/rabbitmq/rabbit-pub.pem >/dev/null
  # Allow other users to see public cert
  sudo chmod 444 /etc/rabbitmq/rabbit-pub.pem
  sudo chown rabbitmq. /etc/rabbitmq/rabbit-pub.pem
else
  if [[ -z "${RABBITMQ_CERT_PUBLIC}" ]]; then
    ctx logger info "No public certificate found."
  else
    ctx logger warn "Public certificate did not appear to be in PEM format."
  fi
  if [[ -f /etc/rabbitmq/rabbit-priv.pem ]]; then
    ctx logger error "Private certificate was provided but public certificate was invalid."
  fi
fi

# Configure rabbit
if [[ -f /etc/rabbitmq/rabbit-priv.pem ]] && [[ -f /etc/rabbitmq/rabbit-pub.pem ]]; then
  echo "[
 {ssl, [{versions, ['tlsv1.2', 'tlsv1.1']}]},
 {rabbit, [
           {loopback_users, []},
           {ssl_listeners, [5671]},
           {ssl_options, [{cacertfile,"'"'"/etc/rabbitmq/rabbit-pub.pem"'"'"},
                          {certfile,  "'"'"/etc/rabbitmq/rabbit-pub.pem"'"'"},
                          {keyfile,   "'"'"/etc/rabbitmq/rabbit-priv.pem"'"'"},
                          {versions, ['tlsv1.2', 'tlsv1.1']}
                         ]}
          ]}
]." | sudo tee /etc/rabbitmq/rabbitmq.config >/dev/null
else
  echo '[{rabbit, [{loopback_users, []}]}].' | sudo tee /etc/rabbitmq/rabbitmq.config >/dev/null
fi

ctx logger info "Stopping RabbitMQ Service..."
set +e
sudo systemctl stop cloudify-rabbitmq.service
if [[ $? -eq 143 ]]; then
        if [[ $? -ne 0 ]]; then
                exit $?
        fi
fi
