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

void main()
{
	//Establish connection to DBus.
	Connection conn = connectToBus();

	//Set up message router.
	MessageRouter router = new MessageRouter();

	//Setup handler
	int uid = cast(int)syscall(GETUID);
	Handlers handler = new Handlers(uid);

	//Register methods
	registerMethods(router, "/wallpaper", "dk.eclipsingr.nice.wallpaper", handler);

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
		this.controller.Start();
	}

	public Event OnNextWallpaper = new Event();
	public Event OnPrevWallpaper = new Event();
	public Event OnSetWallpapers = new Event();
	public Event OnSetAdvanceTime = new Event();

	public string next() {
		OnNextWallpaper(cast(void*)this, null);
		return current();
	}

	public string previous() {
		OnPrevWallpaper(cast(void*)this, null);
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

class Settings {
	mixin JsonizeMe;

	public @jsonize int timeout;
	public @jsonize string[] wallpapers;
}

class Controller {
	public string[] wallpapers = [];
	public int current_wallpaper = 0;
	
	public int timeout = 5;

	public int user_id;
	public string home_root;

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
		this.home_root = GetHomeDirectory();

		if (!std.file.exists(this.home_root~"/.config/nicewallpaperd.json"))
		{
			writeln("<Warn> No settings found in ", this.home_root, "/.config/nicewallpaperd.json!");
			return;
		}
		File f = File(this.home_root~"/.config/nicewallpaperd.json", "r");
		ubyte[] txt;
		foreach(ubyte[] t; f.byChunk(4096)) {
			txt ~= t;
		}
		f.close();
		JSONValue val = parseJSON(cast(string)txt);
		
		Settings set = val.fromJSON!Settings();
		this.timeout = set.timeout;
		this.wallpapers = set.wallpapers;
		if (this.wallpapers.length > 0) SystemSetWallpaper(this.wallpapers[0]);
		writeln("<Info> Settings loaded from ", this.home_root, "/.config/nicewallpaperd.json...");
	}

	void UpdateLoop() {
		while (!should_kill_thread) {
			NextWallpaper(cast(void*)this, null);
			this.updater_thread.sleep(dur!"seconds"(timeout));
		}
	}

	void NextWallpaper(void* sender, EventArgs args) {
		if (wallpapers.length == 0) return;
		current_wallpaper++;
		if (current_wallpaper >= wallpapers.length) current_wallpaper = 0;
		SystemSetWallpaper(this.wallpapers[this.current_wallpaper]);
		writeln("<INFO> Set wallpaper to ", current_wallpaper, " @", wallpapers[current_wallpaper], "...");
	}

	void PreviousWallpaper(void* sender, EventArgs args) {
		if (wallpapers.length == 0) return;
		current_wallpaper--;
		if (current_wallpaper < 0) current_wallpaper = cast(int)wallpapers.length-1;
		SystemSetWallpaper(this.wallpapers[this.current_wallpaper]);
		writeln("<INFO> Set wallpaper to ", current_wallpaper, " @", wallpapers[current_wallpaper], "...");
	}

	void SetWallpaperList(void* sender, EventArgs argz) {
		SetWallpaperEventArgs args = cast(SetWallpaperEventArgs)argz;
		this.wallpapers = args.wallpapers;
		this.current_wallpaper = 0;

		//Save changes.
		Save();
	}

	void SetAdvanceTime(void* sender, EventArgs argz) {
		SetWallpaperAdvanceEventArgs args = cast(SetWallpaperAdvanceEventArgs)argz;
		this.timeout = args.time;

		//Save changes.
		Save();
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
		if (s.getString("picture-options") == "none") {
			s.reset("picture-options");
		}
		s.apply();
		s.sync();
	}

	void Save() {
		File f = File(this.home_root~"/.config/nicewallpaperd.json", "w+");
		Settings s = new Settings();
		s.wallpapers = this.wallpapers;
		s.timeout = this.timeout;
		string st = toJSONString(s);
		if (st != "") f.write(st);
		writeln("<INFO> Saved changes to file... ");
	}

	string GetHomeDirectory() {
		return this.user_iface_prop.Get("org.freedesktop.Accounts.User", "HomeDirectory").to!string();
	}
}