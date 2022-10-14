# This is a sneaky workaround in order to not have to make two separate
# dhcp4.json configuration files for the two DHCP services, since this is the
# only line that needs to differ.
# Inject the desired name with the help of an environment variable in the
# docker-compose file.
echo "\"this-server-name\": \"${THIS_SERVER_NAME}\"," > /tmp/this-server-name.json
