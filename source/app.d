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

static import gio.Settings;
static import std.file;

void main() {
	//Establish connection to DBus.
	Connection conn = connectToBus();

	//Set up message router.
	MessageRouter router = new MessageRouter();

	//Setup handler
	int uid = cast(int)syscall(GETUID);
	Handlers handler = new Handlers(uid);

	//Register methods
	registerMethods(router, "/dk/eclipsingr/nice/wallpaper", "dk.eclipsingr.nice.wallpaper", handler);

	//Register router and run loop.
	writeln("<INFO> Starting from UID ", uid, "...");

	registerRouter(conn, router);
	bool gotem = requestName(conn, "dk.eclipsingr.nice");
	while (true) {
		conn.tick();
	}
}

class SetWallpaperEventArgs : EventArgs {
	public string[] wallpapers;

	this(string[] wallpapers) {
		this.wallpapers = wallpapers;
	}
}

class SetWallpaperOptionsEventArgs : EventArgs {
	public Options option;

	this(Options option) {
		this.option = option;
	}
}


class SetWallpaperAdvanceEventArgs : EventArgs {
	public int time;

	this (int time) {
		this.time = time;
	}
}

class Handlers {
	private Controller controller;

	this(int uid) {
		this.controller = new Controller(uid);
		this.OnNextWallpaper += &controller.NextWallpaper;
		this.OnPrevWallpaper += &controller.PreviousWallpaper;
		this.OnSetWallpapers += &controller.SetWallpaperList;
		this.OnSetAdvanceTime += &controller.SetAdvanceTime;
		this.OnSetWallpaperOptions += &controller.SetWallpaperOptions;
		this.controller.Start();
	}

	public Event OnNextWallpaper = new Event();
	public Event OnPrevWallpaper = new Event();
	public Event OnSetWallpapers = new Event();
	public Event OnSetAdvanceTime = new Event();
	public Event OnSetWallpaperOptions = new Event();

	public string next() {
		OnNextWallpaper(null, null);
		return current();
	}

	public string previous() {
		OnPrevWallpaper(null, null);
		return current();
	}

	public string current() {
		return this.controller.wallpapers[this.controller.current_wallpaper];
	}

	public string[] list() {
		return this.controller.wallpapers;
	}

	public int timeout() {
		return this.controller.timeout;
	}

	public string set_advance_time(int seconds) {
		try {
			OnSetAdvanceTime(cast(void*)this, new SetWallpaperAdvanceEventArgs(seconds));
			return "success";
		} catch (Exception ex) {
			writeln(ex);
			return ex.message.text;
		}
	}

	public string set_wallpaper_option(int option) {
		try {
			ubyte o = cast(ubyte)option;
			if (o > 6) o = 7;
			if (o < 0) o = 0;
			OnSetWallpaperOptions(cast(void*)this, new SetWallpaperOptionsEventArgs(cast(Options)o));
			return "success: " ~ get_option(cast(Options)o);
		} catch (Exception ex) {
			return ex.message.text;
		}
	}

	public string set_wallpaper_list(string[] wallpapers) {
		try {
			OnSetWallpapers(cast(void*)this, new SetWallpaperEventArgs(wallpapers));
			return "success";
		} catch (Exception ex) {
			return ex.message.text;
		}
	}
}

string get_option(Options o) {
	switch (o) {
		case Options.None:
			return "none";
		case Options.Zoom:
			return "zoom";
		case Options.Wallpaper:
			return "wallpaper";
		case Options.Stretched:
			return "stretched";
		case Options.Spanned:
			return "spanned";
		case Options.Scaled:
			return "scaled";
		case Options.Centered:
			return "centered";
		default:
			return "none";
	}
}

enum Options {
	None = 0,
	Wallpaper = 1,
	Centered = 2,
	Scaled = 3,
	Stretched = 4,
	Zoom = 5,
	Spanned = 6
}

class Settings {
	mixin JsonizeMe;

	public @jsonize bool legacy;
	public @jsonize int timeout;
	public @jsonize Options option;
	public @jsonize string[] wallpapers;
}

class Controller {
	public string[] wallpapers = [];
	public int current_wallpaper = 0;
	
	public int timeout = 5;

	public int user_id;
	public bool legacy;
	public string home_root;
	public Options w_option;

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
		this.w_option = set.option;
		if (this.wallpapers.length > 0) SystemSetWallpaper(this.wallpapers[0]);
		SystemSetOption(get_option(this.w_option));

		// Logging.
		writeln("<Info> Settings loaded from ", this.home_root, "/.config/nicewallpaperd.json...");
	}

	bool thread_killed = false;
	void UpdateLoop() {
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

	void SetWallpaperList(void* sender, EventArgs argz) {
		SetWallpaperEventArgs args = cast(SetWallpaperEventArgs)argz;
		if (args.wallpapers.length == 0) return;
		this.wallpapers = args.wallpapers;
		this.current_wallpaper = 0;

		SystemSetWallpaper(this.wallpapers[this.current_wallpaper]);
		force_advance();

		//Save changes.
		Save();
	}

	void SetWallpaperOptions(void* sender, EventArgs argz) {
		SetWallpaperOptionsEventArgs args = cast(SetWallpaperOptionsEventArgs)argz;
		this.w_option = args.option;

		SystemSetOption(get_option(this.w_option));

		Save();
	}

	void SetAdvanceTime(void* sender, EventArgs argz) {
		SetWallpaperAdvanceEventArgs args = cast(SetWallpaperAdvanceEventArgs)argz;
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

	void SystemSetWallpaper(string wallpaper) {
		// If no wallpapers are present, don't try setting nothing as a wallpaper.
		if (wallpapers.length == 0) return;

		//DBus set wallpaper
		this.user_iface.SetBackgroundFile(wallpaper);

		//GIO (GNOME Based) set wallpaper
		gio.Settings.Settings s = new gio.Settings.Settings("org.gnome.desktop.background");
		s.setString("picture-uri", wallpaper);
		s.reset("color-shading-type");
		if (s.getString("picture-options") == "none")
			s.reset("picture-options");
		s.apply();
		s.sync();
	}

	void Save() {
		File f = File(this.home_root~"/.config/nicewallpaperd.json", "w+");
		Settings s = new Settings();
		s.wallpapers = this.wallpapers;
		s.timeout = this.timeout;
		s.option = this.w_option;
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