#!/bin/bash

# Define the name of the virtual bridge
BRIDGE_NAME="virtual_bridge"

# Define the name of the virtual interface
VIRTUAL_INTERFACE="veth0"

# Define the name of the main connection
MAIN_CONNECTION="internet"

# Function to check if an interface is up
is_interface_up() {
    ip link show "$1" up &> /dev/null
}

# Function to check if an interface is part of any bridge
is_interface_in_bridge() {
    [[ $(brctl show | grep "$1") ]]
}

# Function to get the list of active network interfaces
get_active_interfaces() {
    ip link show up | grep -E "^[0-9]+" | awk '{print $2}' | cut -d ':' -f 1
}

# Function to clean up existing bridge and interfaces
cleanup() {
    echo "Cleaning up existing bridge and interfaces..."
    ip link set dev "$BRIDGE_NAME" down &> /dev/null
    ip link delete "$BRIDGE_NAME" type bridge &> /dev/null

    # Check if any interfaces are part of any bridge and remove them
    for interface in $(ls /sys/class/net); do
        if is_interface_in_bridge "$interface" && [ "$interface" != "$VIRTUAL_INTERFACE" ]; then
            echo "Removing interface $interface from existing bridge..."
            ip link set dev "$interface" nomaster
        fi
    done

    # Remove the virtual interface
    ip link delete "$VIRTUAL_INTERFACE" &> /dev/null
}

# Function to create or update the virtual bridge
update_bridge() {
    # Check if the bridge already exists
    if ! is_interface_up "$BRIDGE_NAME"; then
        # Create the virtual bridge
        ip link add name "$BRIDGE_NAME" type bridge
        ip link set dev "$BRIDGE_NAME" up
    fi

    # Check if the virtual interface exists
    if ! is_interface_up "$VIRTUAL_INTERFACE"; then
        # Create the virtual interface
        ip link add name "$VIRTUAL_INTERFACE" type veth peer name "${VIRTUAL_INTERFACE}_peer"
        ip link set dev "$VIRTUAL_INTERFACE" up
    fi

    # Add or update the virtual interface in the bridge
    ip link set dev "${VIRTUAL_INTERFACE}_peer" master "$BRIDGE_NAME"
}

# Function to set the virtual bridge as the main connection
set_main_connection() {
    # Bring down the main connection
    ip link set dev "$MAIN_CONNECTION" down || true

    # Check if the main connection exists in any bridge and remove it
    if is_interface_in_bridge "$MAIN_CONNECTION"; then
        ip link set dev "$MAIN_CONNECTION" nomaster || true
    fi

    # Set the virtual bridge as the main connection
    ip link set dev "$BRIDGE_NAME" name "$MAIN_CONNECTION" || true
    ip link set dev "$MAIN_CONNECTION" up || true
}

# Trap exit signal to call the cleanup function
trap cleanup EXIT

# Run cleanup initially to clean up any existing bridge connections
cleanup

# Watchdog loop
while true; do
    # Get the list of active interfaces
    current_interfaces=$(get_active_interfaces)

    # Check if there are changes in the network interfaces
    if [ "$current_interfaces" != "$previous_interfaces" ]; then
        echo "Network interfaces have changed. Updating the bridge..."
        # Call the function to update the virtual bridge
        update_bridge

        # Call the function to set the virtual bridge as the main connection
        set_main_connection

        # Update the previous interfaces for the next iteration
        previous_interfaces="$current_interfaces"
    fi

    # Sleep for a short duration before checking again
    sleep 5
done
