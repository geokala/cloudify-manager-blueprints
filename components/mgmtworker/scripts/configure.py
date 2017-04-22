#!/usr/bin/env python
#########
# Copyright (c) 2016 GigaSpaces Technologies Ltd. All rights reserved
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
#  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  * See the License for the specific language governing permissions and
#  * limitations under the License.

import tempfile

from os.path import join, isfile, dirname

from cloudify import ctx

ctx.download_resource(
    join('components', 'utils.py'),
    join(dirname(__file__), 'utils.py'))
import utils  # NOQA


MGMT_WORKER_SERVICE_NAME = 'mgmtworker'
CONFIG_PATH = "components/mgmtworker/config"
ctx_properties = utils.ctx_factory.create(MGMT_WORKER_SERVICE_NAME)
MGMTWORKER_USER = ctx_properties['os_user']
MGMTWORKER_GROUP = ctx_properties['os_group']
HOMEDIR = ctx_properties['os_homedir']


def configure_mgmtworker():
    # these must all be exported as part of the start operation.
    # they will not persist, so we should use the new agent
    # don't forget to change all localhosts to the relevant ips
    mgmtworker_home = '/opt/mgmtworker'
    mgmtworker_venv = '{0}/env'.format(mgmtworker_home)
    celery_work_dir = '{0}/work'.format(mgmtworker_home)

    ctx.instance.runtime_properties['file_server_root'] = \
        utils.MANAGER_RESOURCES_HOME

    ctx.logger.info('Configuring Management worker...')
    # Deploy the broker configuration
    if isfile(join(mgmtworker_venv, 'bin/python')):
        broker_conf_path = join(celery_work_dir, 'broker_config.json')
        utils.deploy_blueprint_resource(
            '{0}/broker_config.json'.format(CONFIG_PATH), broker_conf_path,
            MGMT_WORKER_SERVICE_NAME)
        # The config contains credentials, do not let the world read it
        utils.sudo(['chmod', '440', broker_conf_path])
        utils.chown(MGMTWORKER_USER, MGMTWORKER_GROUP, broker_conf_path)
    utils.systemd.configure(MGMT_WORKER_SERVICE_NAME)
    utils.logrotate(MGMT_WORKER_SERVICE_NAME)


def configure_logging():
    ctx.logger.info('Configuring Management worker logging...')
    logging_config_dir = '/etc/cloudify'
    config_name = 'logging.conf'
    config_file_destination = join(logging_config_dir, config_name)
    config_file_source = join(CONFIG_PATH, config_name)
    utils.mkdir(logging_config_dir)
    config_file_temp_destination = join(tempfile.gettempdir(), config_name)
    ctx.download_resource(config_file_source, config_file_temp_destination)
    utils.move(config_file_temp_destination, config_file_destination)


def prepare_snapshot_permissions():
    pgpass_location = '/root/.pgpass'
    destination = join(HOMEDIR, '.pgpass')
    utils.chmod('400', pgpass_location)
    utils.chown(MGMTWORKER_USER, MGMTWORKER_GROUP, pgpass_location)
    utils.sudo(['mv', pgpass_location, destination])
    utils.sudo(['chgrp', MGMTWORKER_GROUP, '/opt/manager'])
    utils.sudo(['chmod', 'g+rw', '/opt/manager'])

    utils.sudo(['/opt/cloudify/snapshot_permissions_fixer'])


configure_mgmtworker()
configure_logging()
prepare_snapshot_permissions()
