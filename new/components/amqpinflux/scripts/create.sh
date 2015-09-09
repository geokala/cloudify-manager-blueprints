#!/bin/bash -e

. $(ctx download-resource "components/utils")


export AMQPINFLUX_HOME="/opt/amqpinflux"
export AMQPINFLUX_VIRTUALENV_DIR="${AMQPINFLUX_HOME}/env"
export AMQPINFLUX_SOURCE_URL=$(ctx node properties amqpinflux_module_source_url)  # (e.g. "https://github.com/cloudify-cosmo/cloudify-amqp-influxdb/archive/3.2.zip")

export RABBITMQ_USERNAME="$(ctx node properties rabbitmq_username)"
export RABBITMQ_PASSWORD="$(ctx node properties rabbitmq_password)"
export RABBITMQ_CERT_PUBLIC="$(ctx node properties rabbitmq_ca_cert)"

ctx logger info "Installing AQMPInflux..."

copy_notice "amqpinflux"
create_dir "${AMQPINFLUX_HOME}"
if [[ "${RABBITMQ_CERT_PUBLIC}" =~ "BEGIN CERTIFICATE" ]]; then
  AMQP_CERT_PATH="${AMQPINFLUX_HOME}/amqp_pub.pem"
  ctx logger info "Found public certificate for rabbitmq."
  echo "${RABBITMQ_CERT_PUBLIC}" | sudo tee "${AMQP_CERT_PATH}" >/dev/null
  sudo chmod 444 "${AMQP_CERT_PATH}"
else
  if [[ -z "${RABBITMQ_CERT_PUBLIC}" ]]; then
    ctx logger info "No public certificate found."
  else
    ctx logger warn "Public certificate did not appear to be in PEM format."
  fi
fi

if [[ -z "${AMQP_CERT_PATH}" ]]; then
  AMQP_PORT="5672"
else
  AMQP_PORT="5671"
fi

copy_notice "amqpinflux"
create_virtualenv "${AMQPINFLUX_VIRTUALENV_DIR}"
install_module ${AMQPINFLUX_SOURCE_URL} "${AMQPINFLUX_VIRTUALENV_DIR}"
configure_systemd_service "amqpinflux"
inject_service_env_var "(( amqp_cert_path ))" "${AMQP_CERT_PATH}" "amqpinflux"
inject_service_env_var "(( amqp_port ))" "${AMQP_PORT}" "amqpinflux"
