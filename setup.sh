#!/bin/bash

DEPLOYED_LIST="deployed_list.txt"
APACHE_CONF_DIR="/etc/apache2/sites-available"
APACHE_PORTS_CONF="/etc/apache2/ports.conf"
START_PORT=8081

# Function to find next available port
get_next_port() {
    port=$START_PORT
    while grep -q "Listen $port" $APACHE_PORTS_CONF; do
        port=$((port+1))
    done
    echo $port
}

while true; do
    choice=$(zenity --list --title="Localhost Web Server Setup" --column="Option" --column="Description" \
        1 "Install Apache2 Web Server" \
        2 "Start Apache2 now" \
        3 "Deploy Homepage Project (New Port)" \
        4 "Show Deployed Ports" \
        5 "Delete Deployment by Port" \
        6 "Exit" --width=500 --height=450)

    case $choice in
        1)
            sudo apt update && sudo apt install apache2 -y
            ;;

        2)
            sudo systemctl start apache2
            ;;

        3)
            homepage=$(zenity --file-selection --title="Select homepage HTML file to deploy")
            if [[ -f "$homepage" ]]; then
                timestamp=$(date +%F_%H-%M-%S)
                deploy_dir="/var/www/html/deploy_$timestamp"
                sudo mkdir "$deploy_dir"
                sudo cp "$homepage" "$deploy_dir/index.html"
                sudo chmod -R 755 "$deploy_dir"

                port=$(get_next_port)

                if ! grep -q "Listen $port" $APACHE_PORTS_CONF; then
                    echo "Listen $port" | sudo tee -a $APACHE_PORTS_CONF
                fi

                conf_file="$APACHE_CONF_DIR/deploy_$timestamp.conf"
                sudo bash -c "cat > $conf_file" <<EOF
<VirtualHost *:$port>
    DocumentRoot "$deploy_dir"
    <Directory "$deploy_dir">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error_$timestamp.log
    CustomLog \${APACHE_LOG_DIR}/access_$timestamp.log combined
</VirtualHost>
EOF

                sudo a2ensite "deploy_$timestamp.conf"
                sudo systemctl reload apache2

                echo "$deploy_dir,$port" >> "$DEPLOYED_LIST"
                zenity --info --text="Deployed at http://localhost:$port"

                zenity --question --text="Open in Firefox now?"
                if [[ $? -eq 0 ]]; then
                    xdg-open "http://localhost:$port"
                fi
            fi
            ;;

        4)
                if [[ ! -s "$DEPLOYED_LIST" ]]; then
                        zenity --info --text="No ports active."
                else
                        deployed_ports=$(awk -F',' '{print $2}' "$DEPLOYED_LIST" | paste -sd'\n')
                        if [[ -z "$deployed_ports" ]]; then
                                zenity --info --text="No ports active."
                        else
                                zenity --info --title="Deployed Ports" --text="$deployed_ports"
                        fi
                fi
                ;;

        5)
            if [[ ! -s "$DEPLOYED_LIST" ]]; then
                zenity --info --text="No deployments to delete!"
            else
                deployed_ports=$(awk -F',' '{print $2}' "$DEPLOYED_LIST")
                if [[ -z "$deployed_ports" ]]; then
                    zenity --info --text="No deployments to delete!"
                else
                    selected_port=$(echo "$deployed_ports" | zenity --list --title="Select Port to Delete" --column="Port" --width=200 --height=300)

                    if [[ -n "$selected_port" ]]; then
                        # Find matching deployment line
                        line=$(grep ",$selected_port\$" "$DEPLOYED_LIST")
                        deploy_dir=$(echo $line | cut -d',' -f1)
                        conf_file="$APACHE_CONF_DIR/$(basename $deploy_dir).conf"

                        # Remove deployment folder
                        sudo rm -rf "$deploy_dir"

                        # Remove conf file
                        sudo a2dissite "$(basename $conf_file)"
                        sudo rm -f "$conf_file"

                        # Remove Listen port line
                        sudo sed -i "/Listen $selected_port/d" $APACHE_PORTS_CONF

                        # Remove from deployed_list.txt
                        grep -vF -- "$line" "$DEPLOYED_LIST" > tmpfile && mv tmpfile "$DEPLOYED_LIST"

                        # Reload Apache
                        sudo systemctl reload apache2

                        zenity --info --text="Deleted deployment on port $selected_port"
                    fi
                fi
            fi
            ;;

                6)
                    break
                    ;;
            esac
        done

