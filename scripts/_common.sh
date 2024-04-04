readonly python_version="$(python3 -V | cut -d' ' -f2 | cut -d. -f1-2)"
readonly code_dir="/opt/yunohost/matrix-$app"
readonly domain_whitelist_client="$(yunohost --output-as json domain list  | jq -r '.domains | .[]')"

install_sources() {
    # Install/upgrade synapse in virtualenv

    # Clean venv is it was on python2.7 or python3 with old version in case major upgrade of debian
    if [ ! -e $code_dir/bin/python3 ] || [ ! -e $code_dir/lib/python$python_version ]; then
        ynh_secure_remove --file=$code_dir/bin
        ynh_secure_remove --file=$code_dir/lib
        ynh_secure_remove --file=$code_dir/lib64
        ynh_secure_remove --file=$code_dir/include
        ynh_secure_remove --file=$code_dir/share
        ynh_secure_remove --file=$code_dir/pyvenv.cfg
    fi

    mkdir -p $code_dir
    chown $app:root -R $code_dir

    if [ -n "$(uname -m | grep arm)" ]
    then
        # Clean old file, sometimes it could make some big issues if we don't do this!!
        ynh_secure_remove --file=$code_dir/bin
        ynh_secure_remove --file=$code_dir/lib
        ynh_secure_remove --file=$code_dir/include
        ynh_secure_remove --file=$code_dir/share

        ynh_setup_source --dest_dir=$code_dir/ --source_id="synapse_prebuilt_armv7_$(lsb_release --codename --short)"

        # Fix multi-instance support
        for f in $(ls $code_dir/bin); do
            if ! [[ $f =~ "__" ]]; then
                ynh_replace_special_string --match_string='#!/opt/yunohost/matrix-synapse' --replace_string='#!'$code_dir --target_file=$code_dir/bin/$f
            fi
        done
    else

        # Install virtualenv if it don't exist
        test -e $code_dir/bin/python3 || python3 -m venv $code_dir

        # Install synapse in virtualenv
        local pip3=$code_dir/bin/pip3

        $pip3 install --upgrade setuptools wheel pip cffi
        $pip3 install --upgrade -r $YNH_APP_BASEDIR/conf/requirement_$(lsb_release --codename --short).txt
    fi

    # Apply patch for LDAP auth if needed
    # Note that we put patch into scripts dir because /source are not stored and can't be used on restore
    if ! grep -F -q '# LDAP Filter anonymous user Applied' $code_dir/lib/python$python_version/site-packages/ldap_auth_provider.py; then
        pushd $code_dir/lib/python$python_version/site-packages
        patch < $YNH_APP_BASEDIR/scripts/patch/ldap_auth_filter_anonymous_user.patch
        popd
    fi
}

configure_coturn() {
    # Get public IP and set as external IP for coturn
    # note : '|| true' is used to ignore the errors if we can't get the public ipv4 or ipv6
    local public_ip4="$(curl -s ip.yunohost.org)" || true
    local public_ip6="$(curl -s ipv6.yunohost.org)" || true

    local turn_external_ip=""
    if [ -n "$public_ip4" ] && ynh_validate_ip4 --ip_address="$public_ip4"
    then
        turn_external_ip+="$public_ip4,"
    fi
    if [ -n "$public_ip6" ] && ynh_validate_ip6 --ip_address="$public_ip6"
    then
        turn_external_ip+="$public_ip6"
    fi
    ynh_add_jinja_config --template="turnserver.conf" --destination="/etc/matrix-$app/coturn.conf"
}

configure_nginx() {
    local e2e_enabled_by_default_client_config

    # Create .well-known redirection for access by federation
    if yunohost --output-as plain domain list | grep -q "^$server_name$"
    then
        local e2e_enabled_by_default_client_config
        if [ $e2e_enabled_by_default == "off" ]; then
            e2e_enabled_by_default_client_config=false
        else
            e2e_enabled_by_default_client_config=true
        fi
        ynh_add_config --template="server_name.conf" --destination="/etc/nginx/conf.d/${server_name}.d/${app}_server_name.conf"
    fi

    # Create a dedicated NGINX config
    ynh_add_nginx_config
}

set_permissions() {
    chown $app:$app -R $code_dir
    chmod o= -R $code_dir

    chmod 770 $code_dir/Coturn_config_rotate.sh
    chmod 700 $code_dir/update_synapse_for_appservice.sh
    chmod 700 $code_dir/set_admin_user.sh

    if [ "${1:-}" == data ]; then
        find $data_dir \(   \! -perm -o= \
                         -o \! -user $app \
                         -o \! -group $app \) \
                    -exec chown $app:$app {} \; \
                    -exec chmod o= {} \;
    fi

    chown $app:$app -R /etc/matrix-$app
    chmod u=rwX,g=rX,o= -R /etc/matrix-$app
    setfacl -R -m user:turnserver:rX  /etc/matrix-$app

    chmod 600 /etc/matrix-$app/$server_name.signing.key

    chown $app:root -R /var/log/matrix-$app
    setfacl -R -m user:turnserver:rwX  /var/log/matrix-$app
}
