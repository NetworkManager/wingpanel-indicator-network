// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2017 elementary LLC. (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Library General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by: David Hewitt <davidmhewitt@gmail.com>
 */

public class Network.ModemInterface : Network.AbstractModemInterface {
    private Wingpanel.Widgets.Switch modem_item;
    private DBusObjectManagerClient? modem_manager;

    private uint32 _signal_quality;
    public uint32 signal_quality {
        get {
            return _signal_quality;
        }
        private set {
            _signal_quality = value;
            if (device.state == NM.DeviceState.ACTIVATED) {
                state = strength_to_state (value);
            }
        }
    }

    public ModemInterface (NM.Client nm_client, NM.RemoteSettings nm_settings, NM.Device? _device) {
        device = _device;
        modem_item = new Wingpanel.Widgets.Switch (display_title);

        notify["display-title"].connect (() => {
            modem_item.set_caption (display_title);
        });

        modem_item.get_style_context ().add_class ("h4");
        modem_item.switched.connect (() => {
            if (modem_item.get_active () && device.state == NM.DeviceState.DISCONNECTED) {
                nm_client.activate_connection (null, device, null, null);
            } else if (!modem_item.get_active () && device.state == NM.DeviceState.ACTIVATED) {
                device.disconnect (() => { debug ("Successfully disconnected."); });
            }
        });

        add (modem_item);

        device.state_changed.connect (() => { update (); });
        prepare.begin ();
    }

    public override void update () {
        switch (device.state) {
            case NM.DeviceState.UNKNOWN:
            case NM.DeviceState.UNMANAGED:
            case NM.DeviceState.UNAVAILABLE:
            case NM.DeviceState.FAILED:
                modem_item.sensitive = false;
                modem_item.set_active (false);
                state = State.FAILED_MOBILE;
                break;    
            case NM.DeviceState.DISCONNECTED:
            case NM.DeviceState.DEACTIVATING:
                modem_item.sensitive = true;
                modem_item.set_active (false);
                state = State.FAILED_MOBILE;
                break;
            case NM.DeviceState.PREPARE:
            case NM.DeviceState.CONFIG:
            case NM.DeviceState.NEED_AUTH:
            case NM.DeviceState.IP_CONFIG:
            case NM.DeviceState.IP_CHECK:
            case NM.DeviceState.SECONDARIES:
                modem_item.sensitive = true;
                modem_item.set_active (true);
                state = State.CONNECTING_MOBILE;
                break;
            case NM.DeviceState.ACTIVATED:
                modem_item.sensitive = true;
                modem_item.set_active (true);
                state = strength_to_state (signal_quality);
                break;
        }
    }

    private Network.State strength_to_state (uint32 strength) {
        if (strength < 30) {
            return Network.State.CONNECTED_MOBILE_WEAK;
        } else if (strength < 55) {
            return Network.State.CONNECTED_MOBILE_OK;
        } else if (strength < 80) {
            return Network.State.CONNECTED_MOBILE_GOOD;
        } else {
            return Network.State.CONNECTED_MOBILE_EXCELLENT;
        }
    }

    private void device_properties_changed (Variant changed) {
        var signal_variant = changed.lookup_value ("SignalQuality", VariantType.TUPLE);
        if (signal_variant != null) {
            bool recent;
            uint32 quality;
            signal_variant.get ("(ub)", out quality, out recent);
            signal_quality = quality;
        }
    }

    public async void prepare () {
        try {
            modem_manager = yield new DBusObjectManagerClient.for_bus (BusType.SYSTEM,
                DBusObjectManagerClientFlags.NONE, "org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1", null);
        } catch (Error e) {
            warning ("Unable to connect to ModemManager1 to check cellular internet signal quality: %s", e.message);
            return;
        }

        modem_manager.interface_proxy_properties_changed.connect ((obj_proxy, interface_proxy, changed, invalidated) => {
            if (interface_proxy.g_object_path == device.get_udi ()) {
                device_properties_changed (changed);
            }
        });
    }
}