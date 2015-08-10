#!/bin/bash -e

. $(ctx download-resource "components/utils")


export CELERY_VERSION=$(ctx node properties celery_version)  # (e.g. 3.1.17)
export REST_CLIENT_SOURCE_URL=$(ctx node properties rest_client_module_source_url)  # (e.g. "https://github.com/cloudify-cosmo/cloudify-rest-client/archive/3.2.zip")
export PLUGINS_COMMON_SOURCE_URL=$(ctx node properties plugins_common_module_source_url)  # (e.g. "https://github.com/cloudify-cosmo/cloudify-plugins-common/archive/3.2.zip")
export SCRIPT_PLUGIN_SOURCE_URL=$(ctx node properties script_plugin_module_source_url)  # (e.g. "https://github.com/cloudify-cosmo/cloudify-script-plugin/archive/1.2.zip")
export REST_SERVICE_SOURCE_URL=$(ctx node properties rest_service_module_source_url)  # (e.g. "https://github.com/cloudify-cosmo/cloudify-manager/archive/3.2.tar.gz")
export DIAMOND_PLUGIN_SOURCE_URL=$(ctx node properties diamond_plugin_module_source_url)
export AGENT_SOURCE_URL=$(ctx node properties agent_module_source_url)

# these must all be exported as part of the start operation. they will not persist, so we should use the new agent
# don't forget to change all localhosts to the relevant ips
export MGMTWORKER_HOME="/opt/mgmtworker"
export VIRTUALENV_DIR="${MGMTWORKER_HOME}/env"
export CELERY_WORK_DIR="${MGMTWORKER_HOME}/work"
export CELERY_LOG_DIR="/var/log/cloudify/mgmtworker"

export RABBITMQ_USERNAME=$"(ctx node properties rabbitmq_username)"
export RABBITMQ_PASSWORD=$"(ctx node properties rabbitmq_password)"
export RABBITMQ_CERT_PUBLIC="$(ctx node properties rabbitmq_cert_public)"

ctx logger info "Installing Management Worker..."

copy_notice "mgmtworker"
create_dir ${MGMTWORKER_HOME}
create_dir ${MGMTWORKER_HOME}/config
create_dir ${CELERY_LOG_DIR}
create_dir ${CELERY_WORK_DIR}

create_virtualenv "${VIRTUALENV_DIR}"

# Add certificate file
if [[ "${RABBITMQ_CERT_PUBLIC}" =~ "BEGIN CERTIFICATE" ]]; then
  BROKER_CERT_PATH="${MGMTWORKER_HOME}/amqp_pub.pem"
  ctx logger info "Found public certificate for rabbitmq."
  echo "${RABBITMQ_CERT_PUBLIC}" | sudo tee "${BROKER_CERT_PATH}" >/dev/null
  sudo chmod 444 "${BROKER_CERT_PATH}"
else
  if [[ -z "${RABBITMQ_CERT_PUBLIC}" ]]; then
    ctx logger info "No public certificate found."
  else
    ctx logger warn "Public certificate did not appear to be in PEM format."
  fi
fi

if [[ -z "${BROKER_CERT_PATH}" ]]; then
  BROKER_PORT=5672
  BROKER_USE_SSL=""
else
  BROKER_PORT=5671
  BROKER_USE_SSL="{ 'ca_certs': '${BROKER_CERT_PATH}', 'cert_reqs': $(python -c 'import ssl; print(ssl.CERT_REQUIRED)') }"
fi

ctx logger info "Installing Management Worker Modules..."
install_module "celery==${CELERY_VERSION}" ${VIRTUALENV_DIR}
install_module ${REST_CLIENT_SOURCE_URL} ${VIRTUALENV_DIR}
install_module ${PLUGINS_COMMON_SOURCE_URL} ${VIRTUALENV_DIR}
# Currently cloudify-agent requires the script and diamond plugins
# so we must install them here. The mgmtworker doesn't use them.
install_module ${SCRIPT_PLUGIN_SOURCE_URL} ${VIRTUALENV_DIR}
install_module ${DIAMOND_PLUGIN_SOURCE_URL} ${VIRTUALENV_DIR}
install_module ${AGENT_SOURCE_URL} ${VIRTUALENV_DIR}

ctx logger info "Downloading cloudify-manager Repository..."
manager_repo=$(download_file ${REST_SERVICE_SOURCE_URL})
ctx logger info "Extracting Manager Repository..."
tar -xzvf ${manager_repo} --strip-components=1 -C "/tmp" >/dev/null

ctx logger info "Installing Management Worker Plugins..."
install_module "/tmp/plugins/riemann-controller" ${VIRTUALENV_DIR}
install_module "/tmp/workflows" ${VIRTUALENV_DIR}

configure_systemd_service "mgmtworker"
inject_management_ip_as_env_var "mgmtworker"
inject_service_env_var "{{ ctx.node.properties.rabbitmq_username }}" "${RABBITMQ_USERNAME}" "mgmtworker"
inject_service_env_var "{{ ctx.node.properties.rabbitmq_password }}" "${RABBITMQ_PASSWORD}" "mgmtworker"
inject_service_env_var "{{ broker_port }}" "${BROKER_PORT}" "mgmtworker"
inject_service_env_var "{{ broker_use_ssl }}" "${BROKER_USE_SSL}" "mgmtworker"
