#!/bin/bash

set -eu

app=__APP__

pushd /etc/yunohost/apps/$app/conf
source /usr/share/yunohost/helpers
source ../scripts/_common.sh

domain=$(ynh_app_setting_get --app=$app --key=domain)
port_cli=$(ynh_app_setting_get --app=$app --key=port_cli)
turnserver_pwd=$(ynh_app_setting_get --app=$app --key=turnserver_pwd)
port_turnserver_tls=$(ynh_app_setting_get --app=$app --key=port_turnserver_tls)
port_turnserver_alt_tls=$(ynh_app_setting_get --app=$app --key=port_turnserver_alt_tls)

previous_checksum=$(ynh_app_setting_get --app=$app --key=checksum__etc_matrix-synapse_coturn.conf)
configure_coturn
new_checksum=$(ynh_app_setting_get --app=$app --key=checksum__etc_matrix-synapse_coturn.conf)

setfacl -R -m user:turnserver:rX  /etc/matrix-$app

if [ "$previous_checksum" != "$new_checksum" ]
then
    systemctl restart $app-coturn.service
fi

exit 0
