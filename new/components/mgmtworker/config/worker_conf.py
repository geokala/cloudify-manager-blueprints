import ssl
# Populated by cloudify workflow
broker_cert_path = '(( broker_cert_path ))'
if broker_cert_path != '':
    BROKER_USE_SSL = {
        'ca_certs': broker_cert_path,
        'cert_reqs': ssl.CERT_REQUIRED,
    }
# Added to config to avoid showing password on service status
BROKER_URL = 'amqp://{{ ctx.node.properties.rabbitmq_username }}:{{ ctx.node.properties.rabbitmq_password }}@{{ ctx.instance.host_ip }}:(( broker_port ))'
