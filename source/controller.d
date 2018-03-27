import syscalld : syscall, GETUID;
import sev.event;
import jsonizer;
import ddbus;
import ddbus.c_lib;

import core.thread;
import core.time;

import std.stdio;
import std.conv;
import std.json;
import std.datetime;
import std.algorithm;

import settings;
import handlers;
import eventargs;

static import gio.Settings;
static import std.file;

class Controller {
	public Wallpaper[] wallpapers = [];
	public int current_wallpaper = 0;
	
	public int timeout = 5;

	public int user_id;
	public bool legacy;
	public bool clock_intervals;
	public string home_root;
	public Options default_option;

	private Thread updater_thread;
	private bool should_kill_thread = false;

	private Connection conn;
	private PathIface user_iface;
	private PathIface user_iface_prop;

	this(int uid) {
		this.updater_thread = new Thread(&UpdateLoop);
		this.user_id = uid;
		this.conn = connectToBus(DBusBusType.DBUS_BUS_SYSTEM);
		this.user_iface = new PathIface(conn, "org.freedesktop.Accounts", "/org/freedesktop/Accounts/User"~this.user_id.text, "org.freedesktop.Accounts.User");
		this.user_iface_prop = new PathIface(conn, "org.freedesktop.Accounts", "/org/freedesktop/Accounts/User"~this.user_id.text, "org.freedesktop.DBus.Properties");
	}

	void Start() {
		this.ApplySettings();
		this.updater_thread.start();
	}

	void ApplySettings() {

		// Get home directory.
		this.home_root = GetHomeDirectory();

		// Check if a settings file is present.
		if (!std.file.exists(this.home_root~"/.config/nicewallpaperd.json"))
		{
			writeln("<Warn> No settings found in ", this.home_root, "/.config/nicewallpaperd.json!");
			return;
		}

		// If there is, read the file.
		File f = File(this.home_root~"/.config/nicewallpaperd.json", "r");
		ubyte[] txt;
		foreach(ubyte[] t; f.byChunk(4096)) {
			txt ~= t;
		}
		f.close();

		// Parse the JSON
		JSONValue val = parseJSON(cast(string)txt);
		Settings set = val.fromJSON!Settings();

		// Apply settings.
		this.timeout = set.timeout;
		this.wallpapers = set.wallpapers;
		this.legacy = set.legacy;
		this.clock_intervals = set.use_clock_intervals;
		this.default_option = set.default_option;
		if (this.wallpapers.length > 0) SystemSetWallpaper(this.wallpapers[0]);

		// Logging.
		writeln("<Info> Settings loaded from ", this.home_root, "/.config/nicewallpaperd.json...");
	}

	bool thread_killed = false;
	void UpdateLoop() {
		// Return early if timeout is 0.
		if (timeout == 0) return;

		bool first_time = true;
		while (!should_kill_thread) {
			// Just in case, quit the loop if the thread should be killed, and for some reason, the while loop derped.
			if (should_kill_thread) break;

			// First update wallpaper after the first has been shown.
			if (!first_time) NextWallpaper(cast(void*)this, null);

			// Sleep loop, so that a new wallpaper can be chosen.
			int seconds = 0;
			while (seconds < timeout && !should_kill_thread) {
				this.updater_thread.sleep(dur!"seconds"(1));
				seconds++;
			}
			first_time = false;
		}

		// Tell the rest of the program that the thread has been killed.
		thread_killed = true;
	}

	void NextWallpaper(void* sender, EventArgs args) {
		// Escape if no wallpapers are present, then advance.
		if (wallpapers.length == 0) return;
		if (!(sender is null) && clock_intervals) {

			TimeOfDay time = cast(TimeOfDay)Clock.currTime();

			int offset = current_wallpaper+1;
			if (offset >= wallpapers.length) offset = 0;
			if (time < wallpapers[offset].clock_offset) {
				return;
			}
		}
		current_wallpaper++;

		// Cap wallpaper selection.
		if (current_wallpaper >= wallpapers.length) current_wallpaper = 0;

		// Apply wallpaper setting.
		SystemSetWallpaper(this.wallpapers[this.current_wallpaper]);
		writeln("<INFO> Set wallpaper to ", current_wallpaper, " @", wallpapers[current_wallpaper], "...");

		// Make sure that force_advance doesn't deadlock the program.
		if (sender is null) force_advance();
	}

	void PreviousWallpaper(void* sender, EventArgs args) {
		// Escape if no wallpapers are present, then advance.
		if (wallpapers.length == 0) return;
		if (!(sender is null) && clock_intervals) {
			TimeOfDay time = cast(TimeOfDay)Clock.currTime();
			
			int offset = current_wallpaper-1;
			if (offset < 0) offset = cast(int)wallpapers.length-1;
			if (time < wallpapers[offset].clock_offset) {
				return;
			}
		}
		current_wallpaper--;

		// Cap wallpaper selection
		if (current_wallpaper < 0) current_wallpaper = cast(int)wallpapers.length-1;
		
		// Apply wallpaper setting.
		SystemSetWallpaper(this.wallpapers[this.current_wallpaper]);
		writeln("<INFO> Set wallpaper to ", current_wallpaper, " @", wallpapers[current_wallpaper], "...");

		// Make sure that force_advance doesn't deadlock the program.
		if (sender is null) force_advance();
	}

	void force_advance() {
		should_kill_thread = true;
		while (!thread_killed) {}
		spawn_updater();
	}

	void spawn_updater() {
		should_kill_thread = false;
		thread_killed = false;
		this.updater_thread = new Thread(&UpdateLoop);
		this.updater_thread.start();
	}

	// TODO: Readd this, in some form.
	/*void SetWallpaperList(void* sender, EventArgs argz) {
		SetWallpaperEventArgs args = cast(SetWallpaperEventArgs)argz;
		if (args.wallpapers.length == 0) return;
		this.wallpapers = args.wallpapers;
		this.current_wallpaper = 0;

		SystemSetWallpaper(this.wallpapers[this.current_wallpaper]);
		force_advance();

		//Save changes.
		Save();
	}*/

	void AddWallpaper(void* sender, EventArgs argz) {
		AddWallpaperEventArgs args = cast(AddWallpaperEventArgs)argz;
		wallpapers ~= new Wallpaper(args.option, args.file, args.clock_offset.toISOString());

		//Save changes.
		Save();
	}

	void RemoveWallpaper(void* sender, EventArgs argz) {
		RemoveWallpaperEventArgs args = cast(RemoveWallpaperEventArgs)argz;
		if (this.wallpapers.length == 0) return;

		for (int i = 0; i < wallpapers.length; i++)
			if (wallpapers[i].file == args.file)
				wallpapers = remove(wallpapers, i);

		//Save changes.
		Save();
	}

	void ClearWallpapers(void* sender, EventArgs argz) {
		this.wallpapers = [];
		writeln("<INFO> Wallpapers cleared!");
		Save();
	}

	void SetWallpaperOptions(void* sender, EventArgs argz) {
		SetWallpaperOptionsEventArgs args = cast(SetWallpaperOptionsEventArgs)argz;
		this.default_option = args.option;

		SystemSetOption(get_option(this.default_option));

		Save();
	}

	void SetUpdateTime(void* sender, EventArgs argz) {
		SetWallpaperUpdateEventArgs args = cast(SetWallpaperUpdateEventArgs)argz;
		this.timeout = args.time;

		//Save changes.
		Save();
	}

	void SystemSetOption(string option) {
		gio.Settings.Settings s = new gio.Settings.Settings("org.gnome.desktop.background");
		s.setString("picture-options", option);
		s.apply();
		s.sync();
		writeln("<INFO> Set wallpaper option to: ", option, "...");
	}

	void SystemSetWallpaper(Wallpaper wallpaper) {
		// If no wallpapers are present, don't try setting nothing as a wallpaper.
		if (wallpapers.length == 0) return;

		//DBus set wallpaper
		this.user_iface.SetBackgroundFile(wallpaper.file);

		//GIO (GNOME Based) set wallpaper
		gio.Settings.Settings s = new gio.Settings.Settings("org.gnome.desktop.background");
		s.setString("picture-uri", wallpaper.file);
		s.reset("color-shading-type");
		if (s.getString("picture-options") == "none")
			s.reset("picture-options");
		s.apply();
		s.sync();

		if (wallpaper.option != Options.None) SystemSetOption(get_option(wallpaper.option));
		else SystemSetOption(get_option(default_option));
	}

	void Save() {
		File f = File(this.home_root~"/.config/nicewallpaperd.json", "w+");
		Settings s = new Settings();
		s.wallpapers = this.wallpapers;
		s.timeout = this.timeout;
		s.default_option = this.default_option;
		s.use_clock_intervals = this.clock_intervals;
		string st = toJSONString(s);
		if (st != "") f.write(st);
		writeln("<INFO> Saved changes to file... ");
	}

	string GetHomeDirectory() {
		// If legacy, return file://(path)
		if (legacy) 
			return "file://" ~ this.user_iface_prop.Get("org.freedesktop.Accounts.User", "HomeDirectory").to!string();

		// Else, just return the path.
		return this.user_iface_prop.Get("org.freedesktop.Accounts.User", "HomeDirectory").to!string();
	}
}