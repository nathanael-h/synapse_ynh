#!/bin/bash

set -eu

source /usr/share/yunohost/helpers

app=__APP__

db_name=$(ynh_app_setting_get --app=$app --key=db_name)
db_user=$(ynh_app_setting_get --app=$app --key=db_user)
db_pwd=$(ynh_app_setting_get --app=$app --key=db_pwd)
server_name=$(ynh_app_setting_get --app=$app --key=server_name)

if [ -z ${1:-} ]; then
    echo "Usage: set_admin_user.sh user_to_set_as_admin"
    exit 1
fi

ynh_psql_execute_as_root --database=$db_name --sql="UPDATE users SET admin = 1 WHERE name = '@$1:$server_name'"

exit 0
