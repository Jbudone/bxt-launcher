/* window.vala
 *
 * Copyright 2020 Ivan Molodetskikh
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
namespace BxtLauncher {
    [GtkTemplate (ui = "/yalter/BxtLauncher/window.ui")]
    public class Window : Gtk.ApplicationWindow {
        private string? hl_pwd { get; set; }
        private string? hl_ld_library_path { get; set; }
        private string? hl_ld_preload { get; set; }
        private string? bxt_path { get; set; }

        public Window (Gtk.Application app) {
            Object (application: app);

            bxt_path = null;

            try {
                var path = FileUtils.read_link ("/proc/self/exe");
                path = Path.get_dirname (path);
                bxt_path = Path.build_filename (path, "libBunnymodXT.so");
            } catch (FileError e) {
                print ("Error: %s\n", e.message);
            }
        }

        [GtkCallback]
        private void launch_button_clicked_cb (Gtk.Button button) {
            if (hl_pwd == null) {
                get_hl_environment ();
            } else {
                launch_hl ();
            }
        }

        private void get_hl_environment () {
            hl_pwd = null;
            hl_ld_library_path = null;
            hl_ld_preload = null;

            var monitor = SystemMonitor.get_default ();
            monitor.on_process_added.connect (process_added_cb);

            try {
                string[] spawn_args = {"steam", "steam://rungameid/70"};

                GLib.Process.spawn_async (
                    null,
                    spawn_args,
                    null,
                    SpawnFlags.SEARCH_PATH,
                    null,
                    null
                );
            } catch (SpawnError e) {
                print ("Error: %s\n", e.message);
            }
        }

        private void process_added_cb (SystemMonitor monitor, Process process) {
            if (process.cmdline == "hl_linux") {
                monitor.on_process_added.disconnect (process_added_cb);

                try {
                    var env = process.get_env ();

                    if (!env.has_key ("PWD")) {
                        print ("Half-Life environment doesn't have PWD\n");
                    } else {
                        hl_pwd = env["PWD"];
                        hl_ld_library_path = env["LD_LIBRARY_PATH"];
                        hl_ld_preload = env["LD_PRELOAD"];
                    }
                } catch (Error e) {
                    print ("Couldn't read the Half-Life environment: %s", e.message);
                }

                // Close this Half-Life instance.
                Posix.kill (process.pid, Posix.Signal.TERM);

                if (hl_pwd != null) {
                    monitor.on_process_removed.connect (process_removed_cb);
                }
            }
        }

        private void process_removed_cb (SystemMonitor monitor, Process process) {
            if (process.cmdline == "hl_linux") {
                monitor.on_process_removed.disconnect (process_removed_cb);
                launch_hl ();
            }
        }

        private void launch_hl ()
            requires (hl_pwd != null)
            requires (bxt_path != null)
        {
            string[] spawn_args = {"./hl_linux"};
            string[] spawn_env = Environ.get ();

            // Add BXT in the end: gameoverlayrenderer really doesn't like being after BXT.
            var ld_preload = "";
            if (hl_ld_preload != null) {
                ld_preload += @"$hl_ld_preload:";
            }
            ld_preload += bxt_path;

            bool found_pwd = false, found_ld_library_path = false, found_ld_preload = false;
            for (int i = 0; i < spawn_env.length; i++) {
                var v = spawn_env[i];

                if (v.has_prefix ("PWD=")) {
                    found_pwd = true;
                    spawn_env[i] = @"PWD=$hl_pwd";
                }

                if (v.has_prefix ("LD_LIBRARY_PATH=")) {
                    found_ld_library_path = true;
                    if (hl_ld_library_path != null) {
                        spawn_env[i] = @"LD_LIBRARY_PATH=$hl_ld_library_path";
                    }
                }

                if (v.has_prefix ("LD_PRELOAD=")) {
                    found_ld_preload = true;
                    spawn_env[i] = @"LD_PRELOAD=$ld_preload";
                }
            }

            if (!found_pwd) {
                spawn_env += @"PWD=$hl_pwd";
            }
            if (!found_ld_library_path && hl_ld_library_path != null) {
                spawn_env += @"LD_LIBRARY_PATH=$hl_ld_library_path";
            }
            if (!found_ld_preload) {
                spawn_env += @"LD_PRELOAD=$ld_preload";
            }

            debug (@"Spawning:\n\tworking_directory = $hl_pwd\n\targv = $(string.joinv(", ", spawn_args))\n\tenvp =\n\t\t$(string.joinv("\n\t\t", spawn_env))\n");

            try {
                GLib.Process.spawn_async (
                    hl_pwd,
                    spawn_args,
                    spawn_env,
                    0,
                    null,
                    null
                );
            } catch (SpawnError e) {
                print ("Error: %s\n", e.message);
            }
        }
    }
}